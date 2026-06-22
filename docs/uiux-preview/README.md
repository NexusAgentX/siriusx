# SiriusX UI/UX 预览页面

> 硬编码的静态 HTML 预览，展示 SiriusX 平台的设计效果 ฅ'ω'ฅ

---

## 🚀 快速开始

### 方法 1：直接打开（推荐）

在浏览器中打开 `index.html` 文件：

```bash
# macOS
open docs/SiriusX/uiux-preview/index.html

# 或者使用绝对路径
open /Users/moguw/siriusx-lab/siriusx-platform/docs/SiriusX/uiux-preview/index.html
```

### 方法 2：本地服务器

```bash
# 进入预览目录
cd docs/SiriusX/uiux-preview

# 启动简单的 HTTP 服务器
python3 -m http.server 8080

# 或使用 Node.js
npx serve .

# 然后在浏览器访问
# http://localhost:8080
```

---

## 📄 页面清单

| 页面 | 文件名 | 描述 | 亮点 |
|------|--------|------|------|
| **导航页** | `index.html` | 所有预览页面的入口 | 精美卡片式导航 |
| **首页** | `agent-catalog.html` | Agent Catalog 选择页 | Hero 区 + 6 个 Agent 卡片 |
| **任务详情** | `task-detail.html` | 对话界面 + 文件树 | 工具调用可视化 |
| **历史页** | `history.html` | 任务历史列表 | 搜索过滤 + 状态 Badge |
| **登录页** | `login.html` | Session Auth 登录 | 渐变背景 + 居中卡片 |
| **设计系统** | `design-system.html` | 颜色、组件、字体展示 | 完整设计规范 |

---

## 🎨 设计亮点

### 1. 首页 - Agent Catalog

- ✨ **Hero 区域**：渐变背景 (Purple gradient)
- 🎴 **Agent 卡片**：三种背景风格循环（light / parchment / dark）
- 🖼️ **图标系统**：专业 emoji（📦 架构 / 🔍 审查 / 🐛 调试）
- 🎬 **交互动画**：
  - hover: 卡片缩放 1.02x
  - hover: 图标缩放 1.1x（0.5s 缓动）
  - 流畅的阴影过渡

### 2. 任务详情页

- 💬 **对话区域**：左右对齐消息气泡
- 🔧 **工具调用面板**：
  - 黄色左边框高亮
  - 米黄色背景
  - 显示命令和执行时间
- 💭 **思考状态**：斜体灰色文字
- 📁 **文件树面板**：
  - 固定右侧 320px
  - 状态点标记（绿色=创建，蓝色=修改）
  - 文件夹和文件图标

### 3. 历史页

- 🔍 **搜索栏**：带过滤和排序下拉菜单
- 🎴 **任务卡片**：
  - hover: 边框高亮 + 上移
  - active: 缩放 0.99x
  - 显示 Agent、状态、元数据
- 🏷️ **状态 Badge**：
  - Completed: 绿色
  - Running: 蓝色
  - Failed: 红色

### 4. 登录页

- 🌈 **渐变背景**：Purple gradient (全屏)
- 🎴 **登录卡片**：
  - 居中对齐
  - 圆角 16px
  - 阴影效果
- 📝 **表单输入**：
  - focus: 蓝色边框 + 阴影
  - 流畅的过渡动画

### 5. 设计系统页

- 🎨 **颜色色板**：5 种语义色展示
- 🔘 **按钮变体**：Default / Secondary / Outline / Destructive
- 🏷️ **Badge 变体**：Running / Completed / Failed / Queued
- 🔤 **字体系统**：Serif / Sans / Mono

---

## 🎯 设计原则体现

| 原则 | 体现 |
|------|------|
| **透明的异步性** | 工具调用面板显示执行状态和耗时 |
| **可恢复的连续性** | 历史页展示所有任务，支持恢复 |
| **渐进式披露** | 文件树折叠，输入区按需显示 |
| **故障可见性** | 状态 Badge 清晰展示（Failed 红色） |
| **分布式系统约束** | Run Badge 独立于 Task Badge |

---

## 🔧 技术栈

- **纯 HTML + CSS**：无依赖，直接打开即可
- **响应式设计**：适配桌面和移动端（Grid + Flexbox）
- **现代浏览器**：Chrome / Safari / Firefox / Edge

---

## 📊 性能

- **文件大小**：每个页面 < 15KB
- **加载时间**：< 100ms（本地文件）
- **无外部依赖**：无需网络请求

---

## 🔄 下一步

这些是**静态预览**，用于：
- ✅ 评审设计方向
- ✅ 展示给团队
- ✅ 用户测试

实际开发使用：
- 🔨 Next.js 16 SSR
- 🎨 Tailwind CSS v4
- 🧩 React 组件

---

## 💡 反馈

发现设计问题或有改进建议？

1. 在 `UIUX.md` 中查看完整设计规范
2. 提交 Issue 或直接修改这些 HTML 文件
3. 联系设计负责人

---

_浮浮酱制作 · 2026-06-15_ ฅ'ω'ฅ
