# 语境输入法构建与安装

# 应用名称
APP_NAME    := LOInputMethod
BUNDLE_ID   := com.lo.inputmethod.ime
BUILD_DIR   := .build/release
INSTALL_DIR := $(HOME)/Library/Input Methods
BUNDLE_PATH := $(INSTALL_DIR)/$(APP_NAME).app
# 系统级安装目录（DMG 安装器安装到此，make 可能残留副本需清理）
SYSTEM_INSTALL_DIR := /Library/Input Methods
SYSTEM_BUNDLE_PATH := $(SYSTEM_INSTALL_DIR)/$(APP_NAME).app
# lsregister 完整路径（用于 LaunchServices 注册/注销，防止输入法列表重复）
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: build install install-full clean uninstall restart fetch-dict install-dict clean-trash package

## 下载 rime-ice 社区词库到源码 Resources/rime/cn_dicts/
fetch-dict:
	@bash scripts/fetch-dict.sh

## 更新词库会改变已签名资源；重组并验证完整应用后再替换。
install-dict: install-full

## 构建 release 版本
build:
	swift build -c release -Xswiftc -strict-concurrency=minimal

## 构建、下载与签名完成后再替换安装，避免构建失败删除可用版本。
install: install-full

install-full: build fetch-dict
	@bash scripts/assemble-app.sh "$(CURDIR)/.build/install/$(APP_NAME).app"
	@bash scripts/install-local.sh "$(CURDIR)/.build/install/$(APP_NAME).app"

## 重启输入法进程（杀掉后用 open 重新启动，确保驻留）
restart:
	-@killall $(APP_NAME) 2>/dev/null || true
	-@killall TextInputMenuAgent 2>/dev/null || true
	@sleep 1
	@open "$(BUNDLE_PATH)"
	@sleep 2
	@echo "输入法进程已重启并驻留。"

## 清理构建产物
clean:
	swift package clean

## 单独清理废纸篓中残留的旧版输入法副本（预防输入法列表重复）
clean-trash:
	@echo "清理废纸篓中的 $(APP_NAME) 副本..."
	@find "$(HOME)/.Trash" -maxdepth 1 -name "$(APP_NAME)*" -exec rm -rf {} + 2>/dev/null || true
	@echo "废纸篓清理完成。"

## 卸载输入法
uninstall:
	-@killall $(APP_NAME) 2>/dev/null || true
	@# 注销 LaunchServices 注册并删除用户级 bundle
	@"$(LSREGISTER)" -u "$(BUNDLE_PATH)" 2>/dev/null || true
	@rm -rf "$(BUNDLE_PATH)"
	@# 若系统级也存在则一并注销删除（需 sudo）
	@if [ -d "$(SYSTEM_BUNDLE_PATH)" ]; then \
		"$(LSREGISTER)" -u "$(SYSTEM_BUNDLE_PATH)" 2>/dev/null || true; \
		sudo rm -rf "$(SYSTEM_BUNDLE_PATH)" 2>/dev/null || \
			echo "  （系统级副本需手动删除: sudo rm -rf \"$(SYSTEM_BUNDLE_PATH)\"）"; \
	fi
	@killall TextInputMenuAgent 2>/dev/null || true
	@echo "已卸载 $(APP_NAME)。"

## 一键打包发布：构建输入法 + 安装器，生成 .dmg 安装镜像
## 产物：dist/语境输入法-<版本>.dmg，用户下载后双击安装器即可一键安装到系统
package:
	@bash scripts/package.sh
