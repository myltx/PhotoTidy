import SwiftUI

struct SuccessSummaryView: View {
    @ObservedObject var viewModel: PhotoCleanupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color("brand-start"))
                        .frame(width: 140, height: 140)
                        .shadow(color: Color("brand-start").opacity(0.3), radius: 20, y: 10)
                    Image(systemName: "checkmark")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(spacing: 8) {
                    Text("清理完成!").font(.largeTitle).bold()
                    Text("相册现在整洁如新").foregroundColor(.secondary)
                }
                VStack(spacing: 6) {
                    Text("释放空间").font(.caption).foregroundColor(.secondary)
                    Text(viewModel.pendingDeletionTotalSize.fileSizeDescription)
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundColor(Color("brand-start"))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("返回首页")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("brand-start"))
                        .cornerRadius(20)
                }
            }
            .padding()
            .navigationTitle("完成")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
