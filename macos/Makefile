# 语镜输入法构建与安装

# 应用名称
APP_NAME    := LOInputMethod
BUNDLE_ID   := com.lo.inputmethod.ime
BUILD_DIR   := .build/release
INSTALL_DIR := $(HOME)/Library/Input Methods
BUNDLE_PATH := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: build install install-full clean uninstall restart fetch-dict install-dict pre-install clean-trash

## 下载 rime-ice 社区词库到源码 Resources/rime/cn_dicts/
fetch-dict:
	@bash scripts/fetch-dict.sh

## 仅下载词库并部署到已安装的 bundle（不重新构建二进制）
install-dict: fetch-dict
	@echo "部署词库到已安装的 $(APP_NAME).app..."
	@mkdir -p "$(BUNDLE_PATH)/Contents/Resources/rime/cn_dicts"
	@cp -r LOInputMethod/Resources/rime/cn_dicts/* "$(BUNDLE_PATH)/Contents/Resources/rime/cn_dicts/"
	@cp LOInputMethod/Resources/rime/luna_pinyin.dict.yaml "$(BUNDLE_PATH)/Contents/Resources/rime/"
	@# 清理用户 Rime 旧构建产物，强制下次启动重新编译新词典
	@rm -f "$(HOME)/Library/Rime/build/luna_pinyin.table.bin" \
	       "$(HOME)/Library/Rime/build/luna_pinyin.prism.bin" 2>/dev/null || true
	@echo "词库部署完成。请执行 make restart 重启输入法触发重新编译。"

## 构建 release 版本
build:
	swift build -c release

## 安装前清理：先杀进程，再用 rm -rf 直接删除旧 bundle（避免 macOS 移入废纸篓），
## 同时清除废纸篓中已有的历史残留副本，防止 LaunchServices 重复注册
pre-install:
	@echo "=== 安装前清理 ==="
	-@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@if [ -d "$(BUNDLE_PATH)" ]; then \
		echo "删除旧 bundle: $(BUNDLE_PATH)"; \
		rm -rf "$(BUNDLE_PATH)"; \
	fi
	@# 清除废纸篓中所有历史 LOInputMethod 副本，避免 LaunchServices 重复注册
	@find "$(HOME)/.Trash" -maxdepth 1 -name "$(APP_NAME)*.app" -exec rm -rf {} + 2>/dev/null || true
	@echo "清理完成。"

## 安装到输入法目录（仅基础安装，不含 librime）
install: pre-install build fetch-dict
	@echo "安装 $(APP_NAME)..."
	@mkdir -p "$(BUNDLE_PATH)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_PATH)/Contents/Resources/rime"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(BUNDLE_PATH)/Contents/MacOS/$(APP_NAME)"
	@cp LOInputMethod/Info.plist "$(BUNDLE_PATH)/Contents/Info.plist"
	@cp -r LOInputMethod/Resources/rime/* "$(BUNDLE_PATH)/Contents/Resources/rime/"
	@# 重新 ad-hoc 签名整个 bundle，封住 Info.plist/Resources（Sealed Resources），
	@# 并固定签名 Identifier = bundle id，确保 TCC 辅助功能授权稳定不丢失
	@# （未签名/ad-hoc 仅签二进制时，TCC 无法可靠绑定身份，每次重装授权失效）
	@codesign --force --deep --options runtime \
		--identifier "$(BUNDLE_ID)" \
		-s - "$(BUNDLE_PATH)"
	@# 清理用户 Rime 旧构建产物，强制重新编译新词典
	@rm -f "$(HOME)/Library/Rime/build/luna_pinyin.table.bin" \
	       "$(HOME)/Library/Rime/build/luna_pinyin.prism.bin" 2>/dev/null || true
	@echo "安装完成（基础版，需系统已安装 librime）。"

## 完整安装（含 librime 打包，自包含）
install-full: pre-install build fetch-dict
	@echo "安装 $(APP_NAME)（含 librime）..."
	@mkdir -p "$(BUNDLE_PATH)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_PATH)/Contents/Resources/rime"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(BUNDLE_PATH)/Contents/MacOS/$(APP_NAME)"
	@cp LOInputMethod/Info.plist "$(BUNDLE_PATH)/Contents/Info.plist"
	@cp -r LOInputMethod/Resources/rime/* "$(BUNDLE_PATH)/Contents/Resources/rime/"
	@bash scripts/build-librime.sh
	@# 重新 ad-hoc 签名整个 bundle（封住 Info.plist/Resources，固定 Identifier=bundle id），
	@# 确保 TCC 辅助功能授权稳定（详见 install 目标注释）
	@codesign --force --deep --options runtime \
		--identifier "$(BUNDLE_ID)" \
		-s - "$(BUNDLE_PATH)"
	@# 清理用户 Rime 旧构建产物，强制重新编译新词典
	@rm -f "$(HOME)/Library/Rime/build/luna_pinyin.table.bin" \
	       "$(HOME)/Library/Rime/build/luna_pinyin.prism.bin" 2>/dev/null || true
	@echo "安装完成。请在系统设置中添加语镜输入法。"

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
	@find "$(HOME)/.Trash" -maxdepth 1 -name "$(APP_NAME)*.app" -exec rm -rf {} + 2>/dev/null || true
	@echo "废纸篓清理完成。"

## 卸载输入法
uninstall:
	-@killall $(APP_NAME) 2>/dev/null || true
	@rm -rf "$(BUNDLE_PATH)"
	@# 同时清理废纸篓残留
	@find "$(HOME)/.Trash" -maxdepth 1 -name "$(APP_NAME)*.app" -exec rm -rf {} + 2>/dev/null || true
	@echo "已卸载 $(APP_NAME)。"
