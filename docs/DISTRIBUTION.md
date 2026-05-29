# 分发说明

本 App 因使用网易云非公开接口 + 私有 MediaRemote,**无法上架 App Store**。分发方式:notarized DMG 直接下载,定位个人/开源使用。

## 步骤(需 Apple Developer 账号)
1. `./Scripts/build-app.sh` 生成 `dist/Vanessa-Notch.app`。
2. 代码签名(Developer ID Application 证书):
   `codesign --deep --force --options runtime --sign "Developer ID Application: <你的名字>" dist/Vanessa-Notch.app`
3. 打包 DMG:`hdiutil create -volname Vanessa-Notch -srcfolder dist/Vanessa-Notch.app -ov -format UDZO dist/Vanessa-Notch.dmg`
4. 公证:`xcrun notarytool submit dist/Vanessa-Notch.dmg --keychain-profile <profile> --wait`
5. 装订:`xcrun stapler staple dist/Vanessa-Notch.dmg`

> 私有 framework 由 perl 运行时加载、不参与链接,通常不影响 Developer ID 签名;若 hardened runtime 拦截,记录日志按警告态降级,不崩溃。
