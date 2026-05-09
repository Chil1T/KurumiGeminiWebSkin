# KurumiGeminiWebSkin

> Gemini Web 用时崎狂三主题 CSS 皮肤项目。唯一可编辑源文件为 `KurumiskinforAI.css`。

## 作用范围

- 本文件适用于 `C:\Program1\CSS\Forgemini\KurumiGeminiWebSkin` 及其所有子目录。
- 所有 AI Agent（Claude Code 等）在操作本目录时应遵循以下约定。

## 文件角色

| 文件 | 角色 |
|------|------|
| `KurumiskinforAI.css` | **唯一可编辑源文件**，也是默认开发文件 |
| `dist/Kurumiskin.user.css` | 构建产物，同时是最终对外分发文件 |
| `background.base64.txt` | 本地发布输入文件，存放背景图 base64 |
| `build-release.ps1` | 从 AI 源文件生成发行版的标准发布脚本 |

## Agent 默认行为

- 默认只读取、分析、修改 `KurumiskinforAI.css`。
- 默认把 `dist/Kurumiskin.user.css` 视为构建产物/分发文件，不是日常编辑入口。
- 默认不要读取 `background.base64.txt`，除非任务明确涉及发布或背景资源本身。
- 默认不要读取或展开 `dist/Kurumiskin.user.css` 中背景图的大段 base64 内容，除非任务明确需要。

## 工作流

### 本地开发

1. 日常开发、重构、样式调整、选择器修复，先改 `KurumiskinforAI.css`。
2. `KurumiskinforAI.css` 中背景图位置保持占位符，不内嵌大 base64。
3. 非背景样式改动完成后，如需构建，默认生成 `dist/Kurumiskin.user.css`。

### 发行

1. 以 `KurumiskinforAI.css` 为准。
2. 将背景 base64 放入本地 `background.base64.txt`。
3. 通过 `build-release.ps1` 构建：`.\build-release.ps1`
4. 构建产物 `dist/Kurumiskin.user.css` 即是最终分发文件，可直接提交到 Git。

### 允许直接处理发行版的情况

- 构建时，需要把 `KurumiskinforAI.css` 的变更同步到 `dist/Kurumiskin.user.css`。
- 任务明确涉及背景图替换、base64 更新、压缩、迁移或背景相关问题排查。
- 任务明确要求检查最终发行内容是否正确。

## 文档约定

- 面向用户的使用说明以 `dist/Kurumiskin.user.css` 为准。
- 面向开发或 AI 协作的说明应明确指向 `KurumiskinforAI.css`。

---

## 经验教训 / Lessons Learned

以下是从浅色模式适配开发中沉淀的关键技术教训，处理 Gemini Web Angular 样式时优先参考。

### 1. CSS 变量作用域陷阱 (Variable Scoping)

**问题：** Angular 组件宿主（`[_nghost]`）会在局部重新定义 CSS 变量。`:root` 层级的 `!important` 变量声明**无法覆盖**组件局部的变量定义。

```css
/* ❌ 不生效：Angular 组件宿主内部的 --gem-sys-color--on-secondary 优先 */
:root .light-theme {
    --gem-sys-color--on-secondary: rgba(26, 26, 26, 0.8) !important;
}

/* ✅ 生效：直接覆盖 CSS 属性，而非变量 */
.conversation-actions-menu-button {
    background-color: transparent !important;
}
```

**规则：** 对 Angular 组件内部的元素，直接覆盖 CSS 属性 + `!important`，不要依赖覆盖变量。变量覆盖只对组件外部的全局元素有效。

### 2. Material Design 状态层 (State Layers)

**问题：** Material Design 组件使用 `::before`/`::after` 伪元素和 `.mat-mdc-button-persistent-ripple` ripple 层产生视觉状态。按钮的"白色圆圈"背景可能来自这些层，而非按钮元素本身。

```css
/* 必须同时覆盖元素本身和其伪元素 */
.element {
    background-color: transparent !important;
}
.element::before {
    background-color: transparent !important;
}

/* 消除 ripple 状态层 */
.element .mat-mdc-button-persistent-ripple::before {
    display: none !important;
    background: none !important;
}
```

### 3. 主题检测选择器 (Theme Detection)

**问题：** 早期的代码同时使用 `:root .light-theme` 和 `:where(.theme-host):where(.light-theme)`。后者更可靠——前者在 `.light-theme` 恰好位于 `:root` 元素本身时不会匹配。

```css
/* 两种都保留作为 fallback */
:root .light-theme .target,
:where(.theme-host):where(.light-theme) .target {
    /* styles */
}
```

**已知问题：** Gemini Web 的主题切换（系统/浅色/深色）通过 `.theme-host.light-theme` / `.theme-host.dark-theme` / `.theme-host.system-theme` class 控制，位于 Angular 根组件上。

### 4. Angular 选择器优先级 (Angular Specificity)

- Angular 的 `[_ngcontent-ng-xxx]` 属性选择器每个增加约 `(0,1,0)` 的优先级
- 多层嵌套组件容易达到 `(0,6,0)` 以上
- Angular 生成的 CSS 规则不使用 `!important`，因此 `!important` 是可靠的覆盖手段

### 5. Chrome DevTools 诊断方法

当 CSS 覆盖不生效时：

1. **检查 Computed 面板**：查看元素的实际计算后样式，而非仅看 Styles 面板
2. **查看 CSS 变量解析值**：Chrome DevTools 的 Computed 面板会显示 `--gem-sys-color-*` 变量的最终解析值
3. **确认变量来源**：如果 `--gem-sys-color--primary-container` 显示为 `#d3e3fd`（浅蓝），即使在 `:root` 定义了透明，说明 Angular 组件局部变量覆盖了全局声明
4. **使用 DevTools AI**：让 AI 分析元素的实际选择器链和计算后样式，快速定位覆盖失败原因

### 6. 文件编辑注意事项

- 该 CSS 文件使用 **Tab 缩进**，不是空格
- 编码：UTF-8（无 BOM）
- 换行符：CRLF (`\r\n`)
- `Read` 工具的输出格式为 `<行号>\t<文件内容>`，其自带的 `\t` 不是文件内容的一部分
- `Edit` 工具的 `old_string` 必须精确匹配文件中的缩进和换行符，否则会失败

## 故障排查指南 / Troubleshooting Guide

### 样式在浅色模式下不生效

1. 确认 Stylus 已启用该样式
2. 打开 Chrome DevTools → Elements → Computed
3. 选择目标元素，查看 `background-color`、`color` 的最终值
4. 如果显示 Angular 的默认值（如 `#d3e3fd` 浅蓝背景），说明 CSS 变量覆盖被组件作用域拦截
5. 解决方案：直接覆盖 CSS 属性 + `!important`，而非覆盖变量

### 三点菜单按钮白色圆圈

1. 白色圆圈可能来自：按钮自身的 `background-color`、`::before` 伪元素、或 `.mat-mdc-button-persistent-ripple::before`
2. 需要覆盖所有三层：按钮本身 + `::before` + ripple 的 `::before`
3. 覆盖状态需包含：normal、hover、focus、menu-opened

### 缩进不一致导致 Edit 工具匹配失败

如果 Edit 工具报 "String to replace not found in file"：
1. 用 PowerShell/Bash 读取文件原始内容检查确切的空白字符
2. 对比 old_string 中的 Tab/空格是否与文件一致
3. 必要时使用 PowerShell 或 Python 进行字符串替换（绕过 Edit 工具的精确匹配限制）
