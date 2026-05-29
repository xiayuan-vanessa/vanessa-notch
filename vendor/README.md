# 第三方 adapter 产物放置说明

从 https://github.com/ungive/mediaremote-adapter 获取以下两项,放到本目录:

- `vendor/mediaremote-adapter.pl`            （perl 流式脚本）
- `vendor/MediaRemoteAdapter.framework`      （私有 framework,**不链接**,仅运行时由 perl 加载）

打包脚本 `Scripts/build-app.sh` 会把它们拷进 `Vanessa-Notch.app/Contents/Resources/`。
注意:必须传绝对路径给 perl 脚本(已在 AppDelegate.adapterPaths() 处理)。
缺失时 App 不崩溃,仅显示「警告态」空闲胶囊。
