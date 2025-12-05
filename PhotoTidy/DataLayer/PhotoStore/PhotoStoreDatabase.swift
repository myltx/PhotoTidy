import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 负责与 SQLite/FTS 的交互，提供 IndexCatalog 所需的数据检索能力
final class PhotoStoreDatabase {
    private let db: OpaquePointer?
    private let queue = DispatchQueue(label: "PhotoStore.Database")

    init(url: URL? = nil) {
        let baseURL: URL
        if let url {
            baseURL = url
        } else {
            baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("PhotoStore.sqlite") ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("PhotoStore.sqlite")
        }
        var pointer: OpaquePointer?
        if sqlite3_open(baseURL.path, &pointer) != SQLITE_OK {
            pointer = nil
        }
        db = pointer
        configurePragmas()
        createSchema()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func bootstrapIfNeeded(with assets: [PhotoAssetMetadata]) {
        queue.sync {
            guard let db else { return }
            let count = countRows(table: "metadata")
            guard count == 0 else { return }
            sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
            let insertSQL = """
            INSERT OR REPLACE INTO metadata
            (id, capture_date, file_name, media_type, album_name, byte_size, width, height, tags, group_id, decision, palette_start, palette_end, score, blur_score, document_score, similarity_score)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var insertStatement: OpaquePointer?
            sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil)
            let groupSQL = """
            INSERT OR IGNORE INTO groups (id, display_name, confidence) VALUES (?, ?, ?);
            """
            var groupStatement: OpaquePointer?
            sqlite3_prepare_v2(db, groupSQL, -1, &groupStatement, nil)

            let memberSQL = """
            INSERT OR REPLACE INTO group_members (group_id, asset_id, position) VALUES (?, ?, ?);
            """
            var memberStatement: OpaquePointer?
            sqlite3_prepare_v2(db, memberSQL, -1, &memberStatement, nil)

            for (index, asset) in assets.enumerated() {
                bindAsset(asset, statement: insertStatement, index: Int32(index))
                sqlite3_step(insertStatement)
                sqlite3_reset(insertStatement)
                if let groupId = asset.groupIdentifier {
                    bindGroup(groupId: groupId, statement: groupStatement, asset: asset)
                    sqlite3_step(groupStatement)
                    sqlite3_reset(groupStatement)
                    bindText(memberStatement, index: 1, value: groupId)
                    bindText(memberStatement, index: 2, value: asset.id)
                    sqlite3_bind_int(memberStatement, 3, Int32(index))
                    sqlite3_step(memberStatement)
                    sqlite3_reset(memberStatement)
                }
            }
            sqlite3_finalize(insertStatement)
            sqlite3_finalize(groupStatement)
            sqlite3_finalize(memberStatement)
            rebuildFTS()
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    func sequentialAssets(scope: PhotoScope) -> [PhotoAssetMetadata] {
        queue.sync {
            guard let db else { return [] }
            return sequentialAssetsLocked(scope: scope, database: db)
        }
    }

    func groups(kind: PhotoGroupKind) -> [PhotoGroupSnapshot] {
        switch kind {
        case .similar:
            return similarGroups()
        case .skipped:
            return skippedGroups()
        }
    }

    func rankedAssets(kind: PhotoRankedKind) -> [PhotoAssetMetadata] {
        queue.sync {
            guard let db else { return [] }
            var whereClause = ""
            var orderClause = ""
            switch kind {
            case .largeFiles:
                whereClause = " WHERE tags & ? != 0"
                orderClause = " ORDER BY byte_size DESC"
            case .blurred:
                whereClause = " WHERE tags & ? != 0"
                orderClause = " ORDER BY blur_score DESC"
            case .documents:
                whereClause = " WHERE tags & ? != 0"
                orderClause = " ORDER BY document_score DESC"
            case .screenshots:
                whereClause = " WHERE tags & ? != 0"
                orderClause = " ORDER BY capture_date DESC"
            }
            let query = baseMetadataSelect() + whereClause + orderClause
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, query, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(kind.bitmask))
            defer { sqlite3_finalize(statement) }
            return collectAssets(statement)
        }
    }

    func pendingAssets(kind: PhotoPendingKind) -> [PhotoAssetMetadata] {
        queue.sync {
            guard let db else { return [] }
            return pendingAssetsLocked(kind: kind, database: db)
        }
    }

    func updateDecision(for ids: [String], state: PhotoDecisionState) {
        guard !ids.isEmpty else { return }
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
            let placeholders = placeholdersList(count: ids.count)
            let sql = "UPDATE metadata SET decision = ? WHERE id IN (\(placeholders));"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            bindText(statement, index: 1, value: state.rawValue)
            bindIds(ids, statement: statement, startIndex: 2)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
            rebuildFTS()
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    func deleteAssets(ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
            let placeholders = placeholdersList(count: ids.count)

            var memberStatement: OpaquePointer?
            let deleteMembersSQL = "DELETE FROM group_members WHERE asset_id IN (\(placeholders));"
            sqlite3_prepare_v2(db, deleteMembersSQL, -1, &memberStatement, nil)
            bindIds(ids, statement: memberStatement, startIndex: 1)
            sqlite3_step(memberStatement)
            sqlite3_finalize(memberStatement)

            var metadataStatement: OpaquePointer?
            let deleteMetadataSQL = "DELETE FROM metadata WHERE id IN (\(placeholders));"
            sqlite3_prepare_v2(db, deleteMetadataSQL, -1, &metadataStatement, nil)
            bindIds(ids, statement: metadataStatement, startIndex: 1)
            sqlite3_step(metadataStatement)
            sqlite3_finalize(metadataStatement)

            sqlite3_exec(db, "DELETE FROM groups WHERE id NOT IN (SELECT DISTINCT group_id FROM group_members);", nil, nil, nil)
            rebuildFTS()
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    func timelineBuckets() -> [TimelineBucketSnapshot] {
        queue.sync {
            guard let db else { return [] }
            return timelineBucketsLocked(database: db)
        }
    }

    func monthKeys() -> [PhotoAssetMetadata.MonthKey] {
        queue.sync {
            guard let db else { return [] }
            let query = """
            SELECT DISTINCT
                strftime('%Y', datetime(capture_date, 'unixepoch')) AS year,
                strftime('%m', datetime(capture_date, 'unixepoch')) AS month
            FROM metadata
            ORDER BY year DESC, month DESC;
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, query, -1, &statement, nil)
            defer { sqlite3_finalize(statement) }
            var result: [PhotoAssetMetadata.MonthKey] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let year = Int(sqlite3_column_int(statement, 0))
                let month = Int(sqlite3_column_int(statement, 1))
                result.append(PhotoAssetMetadata.MonthKey(year: year, month: month))
            }
            return result
        }
    }

    func dashboardSnapshot() -> DashboardSnapshot {
        queue.sync {
            guard let db else {
                return DashboardSnapshot(
                    generatedAt: Date(),
                    totals: [],
                    progressMeters: [],
                    pendingDeletion: 0,
                    skipped: 0,
                    monthlyHighlights: [],
                    storageUsage: DeviceStorageUsage(totalBytes: 0, usedBytes: 0, freeBytes: 0, clearableBytes: 0)
                )
            }
            let totalsQuery = """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN tags & ? != 0 THEN 1 ELSE 0 END) AS large_files,
                SUM(CASE WHEN tags & ? != 0 THEN 1 ELSE 0 END) AS blurred,
                SUM(CASE WHEN tags & ? != 0 THEN 1 ELSE 0 END) AS screenshots,
                SUM(CASE WHEN tags & ? != 0 THEN 1 ELSE 0 END) AS document,
                SUM(CASE WHEN decision = 'skipped' THEN 1 ELSE 0 END) AS skipped
            FROM metadata;
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, totalsQuery, -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(PhotoClassification.largeFile.rawValue))
            sqlite3_bind_int(statement, 2, Int32(PhotoClassification.blurred.rawValue))
            sqlite3_bind_int(statement, 3, Int32(PhotoClassification.screenshot.rawValue))
            sqlite3_bind_int(statement, 4, Int32(PhotoClassification.document.rawValue))
            defer { sqlite3_finalize(statement) }

            var totalCount = 0
            var largeFiles = 0
            var blurred = 0
            var screenshots = 0
            var documents = 0
            var skipped = 0
            if sqlite3_step(statement) == SQLITE_ROW {
                totalCount = Int(sqlite3_column_int(statement, 0))
                largeFiles = Int(sqlite3_column_int(statement, 1))
                blurred = Int(sqlite3_column_int(statement, 2))
                screenshots = Int(sqlite3_column_int(statement, 3))
                documents = Int(sqlite3_column_int(statement, 4))
                skipped = Int(sqlite3_column_int(statement, 5))
            }
            let similar = similarAssetCount(database: db)
            let palette = [
                ThumbnailPalette(startHex: "#8E9BFF", endHex: "#6677FF"),
                ThumbnailPalette(startHex: "#F2A1A1", endHex: "#FF7C7C"),
                ThumbnailPalette(startHex: "#FEBE8C", endHex: "#FF9A62"),
                ThumbnailPalette(startHex: "#5DD6C0", endHex: "#2BB5A1"),
                ThumbnailPalette(startHex: "#CF8BFF", endHex: "#A44DFF"),
                ThumbnailPalette(startHex: "#7AE1FF", endHex: "#38C0F0"),
                ThumbnailPalette(startHex: "#FFCF9F", endHex: "#FF9D6C")
            ]
            let totals: [DashboardSnapshot.CategoryCount] = [
                .init(label: "总数", value: totalCount, accent: palette[0]),
                .init(label: "大文件", value: largeFiles, accent: palette[1]),
                .init(label: "相似", value: similar, accent: palette[2]),
                .init(label: "截图", value: screenshots, accent: palette[3]),
                .init(label: "文档", value: documents, accent: palette[4]),
                .init(label: "模糊", value: blurred, accent: palette[5]),
                .init(label: "跳过", value: skipped, accent: palette[6])
            ]
            let pendingAssets = pendingAssetsLocked(kind: .pendingDeletion, database: db)
            let pending = pendingAssets.count
            let clean = max(0, totalCount - pending - skipped)
            let progressMeters = [
                DashboardSnapshot.ProgressMeter(title: "清理完成", progress: totalCount == 0 ? 0 : Double(clean) / Double(totalCount), subtitle: "已确认 \(clean) 张"),
                DashboardSnapshot.ProgressMeter(title: "待删区", progress: totalCount == 0 ? 0 : Double(pending) / Double(totalCount), subtitle: "待确认 \(pending) 张"),
                DashboardSnapshot.ProgressMeter(title: "跳过中心", progress: totalCount == 0 ? 0 : Double(skipped) / Double(totalCount), subtitle: "跳过 \(skipped) 张")
            ]
            let highlights = Array(timelineBucketsLocked(database: db).prefix(3))
            let clearableBytes = pendingAssets.reduce(0) { $0 + $1.byteSize }
            let storageUsage = deviceStorageUsage(clearableBytes: clearableBytes)
            return DashboardSnapshot(
                generatedAt: Date(),
                totals: totals,
                progressMeters: progressMeters,
                pendingDeletion: pending,
                skipped: skipped,
                monthlyHighlights: highlights,
                storageUsage: storageUsage
            )
        }
    }

    func resetStore() {
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM metadata;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM metadata_fts;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM groups;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM group_members;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM analysis_results;", nil, nil, nil)
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        }
    }

    func metadata(for ids: [String]) -> [PhotoAssetMetadata] {
        guard !ids.isEmpty else { return [] }
        return queue.sync {
            guard let db else { return [] }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let query = baseMetadataSelect() + " WHERE id IN (\(placeholders))"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, query, -1, &statement, nil)
            for (index, id) in ids.enumerated() {
                bindText(statement, index: Int32(index + 1), value: id)
            }
            defer { sqlite3_finalize(statement) }
            return collectAssets(statement)
        }
    }

    func applyAnalysis(tasks: [AnalysisTask]) {
        guard !tasks.isEmpty else { return }
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
            let updateSQL = """
            UPDATE metadata
            SET blur_score = COALESCE(?, blur_score),
                document_score = COALESCE(?, document_score),
                similarity_score = COALESCE(?, similarity_score)
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil)
            for task in tasks {
                let updates = analysisUpdates(for: task)
                sqlite3_bind_double(statement, 1, updates.blurScore ?? .nan)
                sqlite3_bind_double(statement, 2, updates.documentScore ?? .nan)
                sqlite3_bind_double(statement, 3, updates.similarityScore ?? .nan)
                bindText(statement, index: 4, value: task.assetId)
                sqlite3_step(statement)
                sqlite3_reset(statement)
            }
            sqlite3_finalize(statement)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }
}

private extension PhotoStoreDatabase {
    struct AnalysisUpdatePayload {
        var blurScore: Double?
        var documentScore: Double?
        var similarityScore: Double?
    }

    func configurePragmas() {
        guard let db else { return }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    func createSchema() {
        guard let db else { return }
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS metadata (
                id TEXT PRIMARY KEY,
                capture_date REAL NOT NULL,
                file_name TEXT,
                media_type TEXT,
                album_name TEXT,
                byte_size INTEGER,
                width INTEGER,
                height INTEGER,
                tags INTEGER,
                group_id TEXT,
                decision TEXT,
                palette_start TEXT,
                palette_end TEXT,
                score REAL,
                blur_score REAL,
                document_score REAL,
                similarity_score REAL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_metadata_capture_date ON metadata(capture_date DESC);",
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS metadata_fts USING fts5(
                id UNINDEXED,
                capture_month,
                decision,
                content='metadata',
                content_rowid='rowid'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS groups (
                id TEXT PRIMARY KEY,
                display_name TEXT,
                confidence REAL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS group_members (
                group_id TEXT,
                asset_id TEXT,
                position INTEGER,
                PRIMARY KEY (group_id, asset_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS analysis_results (
                asset_id TEXT,
                task_kind TEXT,
                payload TEXT,
                updated_at REAL,
                PRIMARY KEY (asset_id, task_kind)
            );
            """
        ]
        for statement in statements {
            sqlite3_exec(db, statement, nil, nil, nil)
        }
        let migrations = [
            "ALTER TABLE metadata ADD COLUMN file_name TEXT;",
            "ALTER TABLE metadata ADD COLUMN media_type TEXT;",
            "ALTER TABLE metadata ADD COLUMN album_name TEXT;"
        ]
        for migration in migrations {
            sqlite3_exec(db, migration, nil, nil, nil)
        }
    }

    func baseMetadataSelect() -> String {
        """
        SELECT id, capture_date, file_name, media_type, album_name, byte_size, width, height, tags, group_id, decision, palette_start, palette_end, score, blur_score, document_score, similarity_score
        FROM metadata
        """
    }

    func collectAssets(_ statement: OpaquePointer?) -> [PhotoAssetMetadata] {
        var result: [PhotoAssetMetadata] = []
        guard let statement else { return result }
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(asset(from: statement))
        }
        return result
    }

    func asset(from statement: OpaquePointer) -> PhotoAssetMetadata {
        let id = stringColumn(statement, index: 0)
        let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let fileName = stringColumn(statement, index: 2)
        let mediaTypeRaw = stringColumn(statement, index: 3)
        let albumName = stringColumn(statement, index: 4)
        let byteSize = Int(sqlite3_column_int(statement, 5))
        let width = Int(sqlite3_column_int(statement, 6))
        let height = Int(sqlite3_column_int(statement, 7))
        let tags = PhotoClassification(rawValue: Int(sqlite3_column_int(statement, 8)))
        let groupId = stringColumn(statement, index: 9)
        let decisionRaw = stringColumn(statement, index: 10)
        let startHex = stringColumn(statement, index: 11)
        let endHex = stringColumn(statement, index: 12)
        let score = sqlite3_column_double(statement, 13)
        let blurScore = sqlite3_column_double(statement, 14)
        let documentScore = sqlite3_column_double(statement, 15)
        let similarityScore = sqlite3_column_double(statement, 16)
        return PhotoAssetMetadata(
            id: id,
            captureDate: date,
            fileName: fileName.isEmpty ? "未命名" : fileName,
            byteSize: byteSize,
            pixelWidth: width,
            pixelHeight: height,
            mediaType: PhotoAssetMetadata.MediaType(rawValue: mediaTypeRaw) ?? .photo,
            albumName: albumName.isEmpty ? "所有照片" : albumName,
            tags: tags,
            groupIdentifier: groupId.isEmpty ? nil : groupId,
            decision: PhotoDecisionState(rawValue: decisionRaw) ?? .clean,
            palette: ThumbnailPalette(startHex: startHex.isEmpty ? "#444" : startHex, endHex: endHex.isEmpty ? "#222" : endHex),
            score: score,
            blurScore: blurScore,
            documentScore: documentScore,
            similarityScore: similarityScore
        )
    }

    func stringColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    func bindAsset(_ asset: PhotoAssetMetadata, statement: OpaquePointer?, index: Int32) {
        bindText(statement, index: 1, value: asset.id)
        sqlite3_bind_double(statement, 2, asset.captureDate.timeIntervalSince1970)
        bindText(statement, index: 3, value: asset.fileName)
        bindText(statement, index: 4, value: asset.mediaType.rawValue)
        bindText(statement, index: 5, value: asset.albumName)
        sqlite3_bind_int(statement, 6, Int32(asset.byteSize))
        sqlite3_bind_int(statement, 7, Int32(asset.pixelWidth))
        sqlite3_bind_int(statement, 8, Int32(asset.pixelHeight))
        sqlite3_bind_int(statement, 9, Int32(asset.tags.rawValue))
        if let groupId = asset.groupIdentifier {
            bindText(statement, index: 10, value: groupId)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        bindText(statement, index: 11, value: asset.decision.rawValue)
        bindText(statement, index: 12, value: asset.palette.startHex)
        bindText(statement, index: 13, value: asset.palette.endHex)
        sqlite3_bind_double(statement, 14, asset.score)
        sqlite3_bind_double(statement, 15, asset.blurScore)
        sqlite3_bind_double(statement, 16, asset.documentScore)
        sqlite3_bind_double(statement, 17, asset.similarityScore)
    }

    func bindGroup(groupId: String, statement: OpaquePointer?, asset: PhotoAssetMetadata) {
        bindText(statement, index: 1, value: groupId)
        let groupNumber = groupId.split(separator: "-").last ?? "0"
        let name = "相似组 #\(groupNumber)"
        bindText(statement, index: 2, value: name)
        sqlite3_bind_double(statement, 3, asset.similarityScore)
    }

    func countRows(table: String) -> Int {
        guard let db else { return 0 }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        return 0
    }

    func rebuildFTS() {
        guard let db else { return }
        sqlite3_exec(db, "DELETE FROM metadata_fts;", nil, nil, nil)
        let insert = """
        INSERT INTO metadata_fts(rowid, id, capture_month, decision)
        SELECT rowid,
               id,
               strftime('%Y-%m', datetime(capture_date, 'unixepoch')),
               decision
        FROM metadata;
        """
        sqlite3_exec(db, insert, nil, nil, nil)
    }

    func monthRange(key: PhotoAssetMetadata.MonthKey) -> (start: Date, end: Date) {
        var components = DateComponents()
        components.year = key.year
        components.month = key.month
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: components) ?? Date()
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return (start, end)
    }

    func similarGroups() -> [PhotoGroupSnapshot] {
        queue.sync {
            guard let db else { return [] }
            let query = "SELECT id, display_name, confidence FROM groups ORDER BY confidence DESC;"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, query, -1, &statement, nil)
            guard let stmt = statement else { return [] }
            defer { sqlite3_finalize(stmt) }
            var groups: [PhotoGroupSnapshot] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = stringColumn(stmt, index: 0)
                let displayName = stringColumn(stmt, index: 1)
                let confidence = sqlite3_column_double(stmt, 2)
                let members = membersLocked(for: id, database: db)
                groups.append(PhotoGroupSnapshot(id: id, displayName: displayName, confidence: confidence, members: members))
            }
            return groups
        }
    }

    func skippedGroups() -> [PhotoGroupSnapshot] {
        let skippedAssets = pendingAssets(kind: .skipped)
        guard !skippedAssets.isEmpty else { return [] }
        let grouped = Dictionary(grouping: skippedAssets, by: { $0.monthKey })
        return grouped.keys.sorted { lhs, rhs in
            if lhs.year == rhs.year { return lhs.month > rhs.month }
            return lhs.year > rhs.year
        }.map { key in
            let members = grouped[key] ?? []
            return PhotoGroupSnapshot(
                id: "skip-\(key.description)",
                displayName: "\(key.title) 跳过 \(members.count) 张",
                confidence: 0.6,
                members: members
            )
        }
    }

    func members(for groupId: String) -> [PhotoAssetMetadata] {
        queue.sync {
            guard let db else { return [] }
            return membersLocked(for: groupId, database: db)
        }
    }

    private func membersLocked(for groupId: String, database: OpaquePointer) -> [PhotoAssetMetadata] {
        let query = """
        SELECT m.id, m.capture_date, m.byte_size, m.width, m.height, m.tags, m.group_id, m.decision,
               m.palette_start, m.palette_end, m.score, m.blur_score, m.document_score, m.similarity_score
        FROM group_members gm
        JOIN metadata m ON gm.asset_id = m.id
        WHERE gm.group_id = ?
        ORDER BY gm.position ASC;
        """
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, query, -1, &statement, nil)
        bindText(statement, index: 1, value: groupId)
        defer { sqlite3_finalize(statement) }
        return collectAssets(statement)
    }

    private func sequentialAssetsLocked(scope: PhotoScope, database: OpaquePointer) -> [PhotoAssetMetadata] {
        var query = baseMetadataSelect()
        var statement: OpaquePointer?
        switch scope {
        case .all:
            query += " ORDER BY capture_date DESC"
            sqlite3_prepare_v2(database, query, -1, &statement, nil)
        case .month(let key):
            let range = monthRange(key: key)
            query += " WHERE capture_date BETWEEN ? AND ? ORDER BY capture_date DESC"
            sqlite3_prepare_v2(database, query, -1, &statement, nil)
            sqlite3_bind_double(statement, 1, range.start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, range.end.timeIntervalSince1970)
        }
        defer { sqlite3_finalize(statement) }
        return collectAssets(statement)
    }

    private func pendingAssetsLocked(kind: PhotoPendingKind, database: OpaquePointer) -> [PhotoAssetMetadata] {
        let state = kind == .pendingDeletion ? PhotoDecisionState.pendingDeletion.rawValue : PhotoDecisionState.skipped.rawValue
        let query = baseMetadataSelect() + " WHERE decision = ? ORDER BY capture_date DESC"
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard let stmt = statement else { return [] }
        bindText(stmt, index: 1, value: state)
        defer { sqlite3_finalize(stmt) }
        return collectAssets(stmt)
    }

    private func timelineBucketsLocked(database: OpaquePointer) -> [TimelineBucketSnapshot] {
        let query = """
        SELECT strftime('%Y', datetime(capture_date, 'unixepoch')) AS year,
               strftime('%m', datetime(capture_date, 'unixepoch')) AS month,
               COUNT(*) AS total,
               SUM(CASE WHEN decision = 'pendingDeletion' THEN 1 ELSE 0 END) AS pending,
               SUM(CASE WHEN tags & ? != 0 THEN 1 ELSE 0 END) AS blurred,
               SUM(CASE WHEN tags & ? != 0 THEN 1 ELSE 0 END) AS documents,
               MAX(capture_date) AS cover_date
        FROM metadata
        GROUP BY year, month
        ORDER BY year DESC, month DESC;
        """
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, query, -1, &statement, nil)
        sqlite3_bind_int(statement, 1, Int32(PhotoClassification.blurred.rawValue))
        sqlite3_bind_int(statement, 2, Int32(PhotoClassification.document.rawValue))
        defer { sqlite3_finalize(statement) }
        var buckets: [TimelineBucketSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let year = Int(sqlite3_column_int(statement, 0))
            let month = Int(sqlite3_column_int(statement, 1))
            let total = Int(sqlite3_column_int(statement, 2))
            let pending = Int(sqlite3_column_int(statement, 3))
            let blurred = Int(sqlite3_column_int(statement, 4))
            let documents = Int(sqlite3_column_int(statement, 5))
            let key = PhotoAssetMetadata.MonthKey(year: year, month: month)
            let cover = coverAsset(for: key, database: database)
            buckets.append(
                TimelineBucketSnapshot(
                    id: key.description,
                    monthKey: key,
                    assetCount: total,
                    cover: cover,
                    pendingCount: pending,
                    blurredCount: blurred,
                    documentCount: documents
                )
            )
        }
        return buckets
    }

    private func coverAsset(for key: PhotoAssetMetadata.MonthKey, database: OpaquePointer) -> PhotoAssetMetadata? {
        let range = monthRange(key: key)
        var statement: OpaquePointer?
        let query = baseMetadataSelect() + " WHERE capture_date BETWEEN ? AND ? ORDER BY capture_date DESC LIMIT 1"
        sqlite3_prepare_v2(database, query, -1, &statement, nil)
        sqlite3_bind_double(statement, 1, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, range.end.timeIntervalSince1970)
        defer { sqlite3_finalize(statement) }
        guard let stmt = statement else { return nil }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return asset(from: stmt)
        }
        return nil
    }

    func analysisUpdates(for task: AnalysisTask) -> AnalysisUpdatePayload {
        switch task.kind {
        case .blur:
            return AnalysisUpdatePayload(blurScore: Double.random(in: 0.7...0.99), documentScore: nil, similarityScore: nil)
        case .document:
            return AnalysisUpdatePayload(blurScore: nil, documentScore: Double.random(in: 0.6...0.95), similarityScore: nil)
        case .similarity:
            return AnalysisUpdatePayload(blurScore: nil, documentScore: nil, similarityScore: Double.random(in: 0.75...0.99))
        case .metadata:
            return AnalysisUpdatePayload(blurScore: Double.random(in: 0.3...0.5), documentScore: Double.random(in: 0.3...0.5), similarityScore: Double.random(in: 0.3...0.5))
        }
    }

    func bindText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        guard let statement else { return }
        if let value {
            value.withCString { cString in
                sqlite3_bind_text(statement, index, cString, -1, SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func pendingBytesLocked(database: OpaquePointer) -> Int {
        let query = "SELECT SUM(byte_size) FROM metadata WHERE decision = 'pendingDeletion';"
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard let stmt = statement else { return 0 }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    func similarAssetCount(database: OpaquePointer) -> Int {
        let query = "SELECT COUNT(*) FROM metadata WHERE group_id IS NOT NULL;"
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard let stmt = statement else { return 0 }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    func deviceStorageUsage(clearableBytes: Int) -> DeviceStorageUsage {
        let homePath = NSHomeDirectory()
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: homePath),
           let total = attributes[.systemSize] as? NSNumber,
           let free = attributes[.systemFreeSize] as? NSNumber {
            let totalBytes = total.intValue
            let freeBytes = free.intValue
            let usedBytes = max(0, totalBytes - freeBytes)
            return DeviceStorageUsage(
                totalBytes: totalBytes,
                usedBytes: usedBytes,
                freeBytes: freeBytes,
                clearableBytes: clearableBytes
            )
        }
        return DeviceStorageUsage(totalBytes: 0, usedBytes: 0, freeBytes: 0, clearableBytes: clearableBytes)
    }

    func placeholdersList(count: Int) -> String {
        guard count > 0 else { return "" }
        return Array(repeating: "?", count: count).joined(separator: ",")
    }

    func bindIds(_ ids: [String], statement: OpaquePointer?, startIndex: Int32) {
        for (offset, id) in ids.enumerated() {
            bindText(statement, index: startIndex + Int32(offset), value: id)
        }
    }
}

private extension PhotoRankedKind {
    var bitmask: Int {
        switch self {
        case .largeFiles:
            return PhotoClassification.largeFile.rawValue
        case .blurred:
            return PhotoClassification.blurred.rawValue
        case .documents:
            return PhotoClassification.document.rawValue | PhotoClassification.textHeavy.rawValue
        case .screenshots:
            return PhotoClassification.screenshot.rawValue
        }
    }
}
