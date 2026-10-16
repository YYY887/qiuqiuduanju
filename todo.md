# 开发记录

- [x] Android 正式包名从 `com.duanju.duanju_app` 改为 `com.duanju.qiuqiuduanju`，同步更新 Gradle `namespace`、`applicationId` 和 `MainActivity` 包路径。
- [x] 源码版本递增至 `0.2.72+78`，在 README 记录包名变更，并将本文件纳入源码同步。
- [ ] 待集中验证时检查 Android 构建、安装与启动；新包名会作为独立应用安装，原包名的数据不会自动迁移。
- [x] 新增 GitHub Actions 手动 Android 打包流程，分别生成红果版与全站源版的三个架构签名 APK。
- [ ] 推送源码并运行 Android 工作流，确认 APK Artifact 已生成。
