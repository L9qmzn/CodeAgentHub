# CodeAgent Hub

[English](#english) | [中文](#中文)

---

## English

### Overview

CodeAgent Hub is a full-stack application for interacting with Claude Agent SDK and Codex CLI. It provides a cross-platform Flutter frontend and dual backend implementations (Python/TypeScript) with streaming chat capabilities.

### Features

- **Streaming Chat** - Real-time SSE-based message streaming with Claude AI
- **Multi-Agent Support** - Claude Code and Codex CLI integration
- **Session Management** - Persistent sessions with SQLite storage
- **Cross-Platform** - Windows, macOS, Linux, Android, iOS, and Web
- **User Settings** - Customizable permission modes and system prompts
- **Image Support** - Send images in chat messages

### Project Structure

```
CodeAgentHub/
├── config.yaml              # Shared backend configuration
├── backend/
│   ├── py_backend/          # Python FastAPI backend
│   │   ├── main.py          # Entry point
│   │   ├── app_factory.py   # FastAPI app & routes
│   │   ├── config.py        # Configuration loading
│   │   └── requirements.txt # Python dependencies
│   └── ts_backend/          # TypeScript Express backend
│       ├── src/
│       │   ├── index.ts     # Entry point
│       │   └── app.ts       # Express app & routes
│       ├── package.json     # Node.js dependencies
│       └── tsconfig.json
└── frontend/                # Flutter frontend
    ├── lib/
    │   ├── main.dart        # App entry point
    │   ├── screens/         # UI screens
    │   ├── services/        # API & business logic
    │   └── models/          # Data models
    └── pubspec.yaml         # Flutter dependencies
```

### Prerequisites

- **Python Backend**: Python 3.10+, pip
- **TypeScript Backend**: Node.js 18+, npm
- **Frontend**: Flutter 3.5+, Dart SDK

### Quick Start

#### 1. Configure Backend

Edit `config.yaml` in the project root:

```yaml
claude_dir: ~/.claude        # Claude Desktop session directory
sessions_db: ./sessions.db   # SQLite database path
port: 8207                   # Server port
users:
  admin: your_password       # Basic Auth credentials
verbose_logs: true
```

#### 2. Run Backend (Choose One)

**Python Backend:**
```bash
cd backend/py_backend
pip install -r requirements.txt
python main.py
```

**TypeScript Backend:**
```bash
cd backend/ts_backend
npm install
npm run dev
```

Server starts at `http://127.0.0.1:8207`

#### 3. Run Frontend

```bash
cd frontend
flutter pub get
flutter run -d windows  # or macos, linux, chrome, etc.
```

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/chat` | Stream chat messages (SSE) |
| POST | `/chat/stop` | Stop active chat run |
| GET | `/sessions` | List all sessions |
| GET | `/sessions/{id}` | Get session details |
| POST | `/sessions/load` | Reload sessions from disk |
| GET/PUT | `/users/{id}/settings` | User settings |
| POST | `/codex/chat` | Codex CLI chat (TS only) |

### License

MIT License

---

## 中文

### 概述

CodeAgent Hub 是一个用于与 Claude Agent SDK 和 Codex CLI 交互的全栈应用。提供跨平台 Flutter 前端和双后端实现（Python/TypeScript），支持流式聊天功能。

### 功能特性

- **流式聊天** - 基于 SSE 的实时消息流，与 Claude AI 交互
- **多 Agent 支持** - 集成 Claude Code 和 Codex CLI
- **会话管理** - 使用 SQLite 持久化存储会话
- **跨平台** - 支持 Windows、macOS、Linux、Android、iOS 和 Web
- **用户设置** - 可自定义权限模式和系统提示词
- **图片支持** - 支持在聊天中发送图片

### 项目结构

```
CodeAgentHub/
├── config.yaml              # 共享后端配置
├── backend/
│   ├── py_backend/          # Python FastAPI 后端
│   │   ├── main.py          # 入口文件
│   │   ├── app_factory.py   # FastAPI 应用和路由
│   │   ├── config.py        # 配置加载
│   │   └── requirements.txt # Python 依赖
│   └── ts_backend/          # TypeScript Express 后端
│       ├── src/
│       │   ├── index.ts     # 入口文件
│       │   └── app.ts       # Express 应用和路由
│       ├── package.json     # Node.js 依赖
│       └── tsconfig.json
└── frontend/                # Flutter 前端
    ├── lib/
    │   ├── main.dart        # 应用入口
    │   ├── screens/         # 界面页面
    │   ├── services/        # API 和业务逻辑
    │   └── models/          # 数据模型
    └── pubspec.yaml         # Flutter 依赖
```

### 环境要求

- **Python 后端**: Python 3.10+, pip
- **TypeScript 后端**: Node.js 18+, npm
- **前端**: Flutter 3.5+, Dart SDK

### 快速开始

#### 1. 配置后端

编辑项目根目录的 `config.yaml`：

```yaml
claude_dir: ~/.claude        # Claude Desktop 会话目录
sessions_db: ./sessions.db   # SQLite 数据库路径
port: 8207                   # 服务端口
users:
  admin: your_password       # Basic Auth 认证凭据
verbose_logs: true
```

#### 2. 运行后端（二选一）

**Python 后端：**
```bash
cd backend/py_backend
pip install -r requirements.txt
python main.py
```

**TypeScript 后端：**
```bash
cd backend/ts_backend
npm install
npm run dev
```

服务启动于 `http://127.0.0.1:8207`

#### 3. 运行前端

```bash
cd frontend
flutter pub get
flutter run -d windows  # 或 macos, linux, chrome 等
```

### API 接口

| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/chat` | 流式聊天消息 (SSE) |
| POST | `/chat/stop` | 停止当前聊天 |
| GET | `/sessions` | 获取所有会话列表 |
| GET | `/sessions/{id}` | 获取会话详情 |
| POST | `/sessions/load` | 从磁盘重新加载会话 |
| GET/PUT | `/users/{id}/settings` | 用户设置 |
| POST | `/codex/chat` | Codex CLI 聊天（仅 TS 后端） |

### 开源协议

MIT License
