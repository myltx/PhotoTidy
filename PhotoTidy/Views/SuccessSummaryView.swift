import SwiftUI

struct SuccessSummaryView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    private var freedAmount: (value: String, unit: String) {
        let bytes = max(viewModel.lastFreedSpace, 0)
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return (String(format: "%.1f", gb), "GB")
        }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1 {
            return (String(format: "%.1f", mb), "MB")
        }
        let kb = Double(bytes) / 1024
        if kb >= 1 {
            return (String(format: "%.0f", kb), "KB")
        }
        return ("0", "KB")
    }

    private var freedReadableText: String {
        let bytes = max(viewModel.lastFreedSpace, 0)
        guard bytes > 0 else { return "--" }
        return bytes.fileSizeDescription
    }

    private var deletionCountText: String? {
        viewModel.lastDeletedItemsCount > 0 ? "共删除 \(viewModel.lastDeletedItemsCount) 项内容" : nil
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color("brand-start"), Color("brand-end")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 420, height: 420)
                .blur(radius: 30)
                .offset(y: -220)

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 15)
                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(Color("brand-start"))
                }

                VStack(spacing: 6) {
                    Text("清理完成!")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                    Text("相册现在整洁如新")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                }

                VStack(spacing: 16) {
                    Text("本次释放空间")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(4)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(freedAmount.value)
                            .font(.system(size: 68, weight: .heavy))
                            .foregroundColor(.white)
                            .tracking(-1)
                        Text(freedAmount.unit)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                    }

                    VStack(spacing: 4) {
                        Text("≈ \(freedReadableText)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.85))

                        if let deletionCountText {
                            Text(deletionCountText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .background(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .blur(radius: 30)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 12)

                Text("已将所选照片移至系统“最近删除”。30 天内可在“照片 > 最近删除”恢复或彻底删除。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("返回首页")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .foregroundColor(Color("brand-start"))
                        .cornerRadius(24)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color("brand-start"))
                    .frame(width: 42, height: 42)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
            .padding(.leading, 24)
            .padding(.top, 24)
        }
    }
}
