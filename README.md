# lo 前后端分离开发脚手架

基于 go-zero + React + TypeScript 的优秀前后端分离开发脚手架，提取自生产项目，可直接用于快速搭建新项目。

## 项目结构

```
lo/
├── backend/          # go-zero 后端脚手架
└── frontend/         # React 前端脚手架
```

## 技术栈

### 后端
- **框架**: go-zero v1.10.1
- **数据库**: MySQL 8.0 + Redis 7
- **认证**: JWT
- **代码生成**: goctl
- **部署**: Docker + Docker Compose

### 前端
- **框架**: React 19 + TypeScript + Vite 7
- **状态管理**: Redux Toolkit
- **UI样式**: Tailwind CSS 4
- **路由**: React Router DOM 7
- **HTTP**: Axios（含Token自动刷新）

## 快速开始

### 环境要求
- Go 1.26+
- Node.js 20+
- Docker & Docker Compose

### 启动后端

```bash
cd backend

# 1. 复制环境变量配置文件
cp .env.example .env

# 2. 启动基础设施（MySQL + Redis）
make infra-up

# 3. 安装 goctl 工具
make install

# 4. 生成 API 和 Model 代码
make gen

# 5. 运行服务
make run
```

### 启动前端

```bash
cd frontend

# 1. 安装依赖
npm install

# 2. 复制环境变量配置文件
cp .env.example .env

# 3. 启动开发服务器
npm run dev
```

## 关键文件说明

### 后端
| 文件 | 说明 |
|------|------|
| `service/api/api.api` | API 接口定义（源文件） |
| `service/api/api.go` | 服务入口 |
| `pkg/errno/errno.go` | 错误码体系 |
| `pkg/response/response.go` | 统一响应封装 |
| `pkg/crypto/aes.go` | AES-GCM 加密工具 |
| `internal/middleware/jwtauthmiddleware.go` | JWT 认证中间件 |
| `internal/middleware/ratelimitmiddleware.go` | 限流中间件 |
| `Makefile` | 构建、生成、运行命令 |
| `deploy/docker-compose.base.yml` | 基础设施编排 |

### 前端
| 文件 | 说明 |
|------|------|
| `src/utils/request.ts` | Axios 请求封装（含Token刷新） |
| `src/utils/authStorage.ts` | 认证信息本地存储 |
| `src/store/index.ts` | Redux Store 配置（含持久化中间件） |
| `src/router/index.tsx` | 路由配置（含ProtectedRoute） |
| `src/App.tsx` | 根组件（含ErrorBoundary、ThemeProvider） |

## 使用新项目的步骤

1. 复制 `lo` 目录到新项目
2. 全局替换 `lo-backend` 为你的模块名
3. 全局替换 `lo` 为你的项目名
4. 根据业务需求修改配置
5. 根据业务需求扩展 API 接口和页面组件

## 标注说明

项目已初始化完成，可根据业务需求扩展以下内容：
- API 接口和页面组件
- 业务错误码
- 数据表结构

