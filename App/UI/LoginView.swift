import SwiftUI

/// Not in upstream (it scans local storage); drawn in the settings-panel language.
struct LoginView: View {
    private enum Field: Hashable { case url, user, password }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var url = UserDefaults.standard.string(forKey: "rhine.url") ?? "http://"
    @State private var user = UserDefaults.standard.string(forKey: "rhine.user") ?? ""
    @State private var password = ""
    @FocusState private var focused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RhinePad").font(.mi(22, .bold)).foregroundStyle(palette.ink)
            Text("MUSIC ARCHIVE / NAVIDROME").font(.mi(9.5)).tracking(1.2).foregroundStyle(palette.muted).padding(.top, 2)
            Rectangle().fill(palette.line).frame(height: 1).padding(.vertical, 18)
            field("服务器地址", tag: .url, text: $url, secure: false)
            field("用户名", tag: .user, text: $user, secure: false)
            field("密码", tag: .password, text: $password, secure: true)
            if let error = model.loginError {
                Text(error).font(.mi(12)).foregroundStyle(palette.accent).padding(.top, 4)
            }
            Button {
                model.signIn(url: url, user: user, password: password)
            } label: {
                HStack {
                    Text(model.loggingIn ? "正在连接…" : "连接音乐库").font(.mi(15, .demibold))
                    Spacer()
                    Text("↗").font(.mi(17))
                }
                .foregroundStyle(palette.ink)
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(palette.accent).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(palette.accent).frame(height: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .disabled(model.loggingIn || user.isEmpty || password.isEmpty)
            .padding(.top, 18)
            Text("密码仅保存在本机钥匙串，认证使用 Subsonic token。").font(.mi(11)).foregroundStyle(palette.muted).padding(.top, 10)
        }
        .padding(28)
        .frame(width: 380)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.line))
        .shadow(color: .black.opacity(0.12), radius: 22, y: 10)
    }

    private func field(_ label: String, tag: Field, text: Binding<String>, secure: Bool) -> some View {
        let isFocused = focused == tag
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.mi(11)).foregroundStyle(isFocused ? palette.accent : palette.muted)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .focused($focused, equals: tag)
            .font(.mi(15))
            .foregroundStyle(palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? palette.accent : palette.line)
                    .frame(height: isFocused ? 1.5 : 1)
            }
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .padding(.bottom, 12)
    }
}
