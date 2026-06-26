# 下山算账 · Settle After Descent

一款面向登山徒步小队的精细化出行花费分账 App。

进山前要采购公共食品、车票、保险，借用协会装备可能还要付装备费，通常由一位“财务”统一垫付和记账；活动还会牵扯到进山前、出山后的团建聚餐、打车、KTV 等复杂花销。下山之后，大家就用这款 App 把账算清楚——谁该收钱、谁该付钱、每一笔为什么这么分，都能追溯。

当前版本是 Flutter 单机本地应用，优先面向 Android，后续可扩展到 iOS。所有数据保存在手机本地，不需要账号、不需要联网。

## 功能特性

- 旅行事件管理，支持自定义纯色 / 相册图片背景
- 成员管理与头像展示，参与人支持全选 / 全不选 / 点头像切换
- 简单花费：直接选择一种分摊规则
- 组合花费：拆分为多个子花费，每个子花费独立分摊
- 分摊规则：平均分摊、固定金额、价格等级、优惠抵扣、手动调整
- 多付款人记录
- 花费按 `Month-Day` 排序并分组归档，可加简短备注
- 每人已付 / 应担 / 净额计算
- 结算方案可切换：最短转账路径、统一中转人
- 花费详情页可查看子花费、付款人、分摊规则与分摊结果，并继续编辑
- 表格化导出预览，支持横向滑动
- 导出 CSV 文件、导出铺展开的大图，并可分享到微信等应用
- 接近 iOS 审美的浅色卡片风格，按钮采用“大中文 + 小英文”

## 目录结构

```text
.
├── product-design.md   产品与软件设计文档
├── pubspec.yaml        Flutter 项目配置
├── lib/main.dart       应用全部源码
├── android/            Android 平台工程
├── ios/                iOS 平台工程
└── test/               组件冒烟测试
```

## 环境要求

- Flutter 3.44.x（Dart 3.12.x）
- JDK 21
- Android SDK 36 + build-tools

## 运行与构建

```bash
flutter pub get
flutter run
```

构建 Android 安装包：

```bash
flutter build apk --release
```

产物位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

连接 Android 手机后安装：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 下一步开发建议

- 拆分 `lib/main.dart` 为 models、calculator、screens、widgets
- 接入 SQLite / Drift 做更稳健的本地持久化
- 增加暗色模式
- 增加历史旅行复用成员组
- iOS 端构建与适配（需完整 Xcode 与 CocoaPods）
