# Android 设备连接指南

本文档详细说明如何连接 Android 设备来运行和测试 IgniteList 应用。

## 📱 步骤 1：启用开发者选项和 USB 调试

### 1.1 启用开发者选项

1. 打开 Android 设备的 **设置**
2. 找到 **关于手机**（About phone）或 **关于设备**（About device）
3. 连续点击 **版本号**（Build number）7 次
   - 会看到提示 "您已成为开发者！" 或 "You are now a developer!"
4. 返回设置主页面，现在可以看到 **开发者选项**（Developer options）

### 1.2 启用 USB 调试

1. 进入 **开发者选项**
2. 找到 **USB 调试**（USB debugging）
3. 打开 **USB 调试** 开关
4. （可选）启用 **USB 安装**（USB installation）和 **USB 调试（安全设置）**

---

## 🔌 步骤 2：连接设备到电脑

### 2.1 物理连接

1. 使用 USB 数据线将 Android 设备连接到电脑
2. 确保使用**数据线**（不是仅充电线）

### 2.2 授权 USB 调试

1. 设备上会弹出 **允许 USB 调试？** 对话框
2. 勾选 **始终允许来自这台计算机**
3. 点击 **确定** 或 **允许**

---

## ✅ 步骤 3：验证设备连接

### 3.1 检查设备是否被识别

在项目目录下运行：

```bash
flutter devices
```

**预期输出：**
```
Found X connected devices:
  Android SDK built for x86 • emulator-5554 • android-x86 • Android 11 (API 30)
  SM-G991B (mobile)          • R58M123456    • android-arm64 • Android 13 (API 33)
```

如果看到你的 Android 设备，说明连接成功！

### 3.2 如果设备未显示

**方法 1：检查 ADB 连接**

```bash
adb devices
```

**预期输出：**
```
List of devices attached
R58M123456    device
```

如果显示 `unauthorized`：
- 检查设备上的 USB 调试授权对话框
- 重新连接 USB 线
- 在设备上点击"允许"

**方法 2：安装/更新 USB 驱动**

- **Windows**: 可能需要安装设备制造商提供的 USB 驱动
  - 华为：HiSuite
  - 小米：Mi USB Driver
  - 三星：Samsung USB Driver
  - 通用：Google USB Driver（通过 Android Studio）

**方法 3：检查 USB 连接模式**

在设备上：
1. 下拉通知栏
2. 点击 USB 连接通知
3. 选择 **文件传输**（File Transfer）或 **MTP** 模式

---

## 🚀 步骤 4：运行应用

### 4.1 运行到 Android 设备

```bash
flutter run -d <设备ID>
```

**示例：**
```bash
# 如果只有一个 Android 设备
flutter run

# 或者指定设备 ID
flutter run -d R58M123456
```

### 4.2 查看可用设备

```bash
flutter devices
```

会显示所有可用设备，包括：
- Android 设备（物理设备）
- Android 模拟器
- iOS 设备（如果在 macOS 上）
- Web 浏览器
- Windows/Linux/macOS 桌面

---

## 🔧 常见问题排查

### 问题 1：设备显示为 "unauthorized"

**解决方案：**
1. 在设备上撤销 USB 调试授权
2. 重新连接 USB 线
3. 在设备上重新授权

### 问题 2：设备显示为 "offline"

**解决方案：**
```bash
adb kill-server
adb start-server
adb devices
```

### 问题 3：找不到设备

**检查清单：**
- ✅ USB 调试已启用
- ✅ USB 连接模式正确（文件传输/MTP）
- ✅ USB 数据线支持数据传输
- ✅ USB 驱动已安装（Windows）
- ✅ 设备已授权 USB 调试

### 问题 4：Flutter 找不到设备，但 ADB 可以

**解决方案：**
```bash
flutter doctor -v
```

检查 Android toolchain 配置是否正确。

---

## 📱 使用 Android 模拟器（备选方案）

如果无法连接物理设备，可以使用 Android 模拟器：

### 1. 查看可用模拟器

```bash
flutter emulators
```

### 2. 启动模拟器

```bash
flutter emulators --launch <模拟器名称>
```

或者通过 Android Studio 启动模拟器。

### 3. 运行应用

```bash
flutter run
```

---

## 🎯 快速检查清单

在运行应用前，确保：

- [ ] Android 设备已启用开发者选项
- [ ] USB 调试已启用
- [ ] 设备已通过 USB 连接到电脑
- [ ] 设备上已授权 USB 调试
- [ ] `flutter devices` 可以检测到设备
- [ ] 设备上已安装必要的应用（首次运行会自动安装）

---

## 💡 提示

1. **首次连接**：第一次连接时，设备上会弹出授权对话框，务必点击"允许"
2. **无线调试**（Android 11+）：如果 USB 连接有问题，可以尝试无线调试
3. **热重载**：应用运行后，按 `r` 键可以热重载，`R` 键可以热重启
4. **查看日志**：应用运行时会自动显示日志，也可以使用 `flutter logs` 查看

---

## 🎉 成功运行后

应用成功安装到设备后，你可以：

1. **测试功能**：
   - 添加待办事项
   - 完成待办事项（查看庆祝动画和"N连胜！"）
   - 删除待办事项
   - 测试每日重置功能

2. **查看效果**：
   - 夸张的庆祝动画
   - 连续完成天数显示
   - 音效播放（如果已添加音效文件）

3. **调试**：
   - 使用 `flutter logs` 查看日志
   - 使用 `r` 进行热重载
   - 使用 `q` 退出应用

---

*最后更新：2025-12-02*

