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

.PHONY: build install install-full clean uninstall restart fetch-dict install-dict pre-install clean-trash package

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
	swift build -c release -Xswiftc -strict-concurrency=minimal

## 安装前清理：先杀进程，再删除所有位置的旧 bundle，
## 注销旧 LaunchServices 注册，清除废纸篓残留，防止输入法列表出现重复项
pre-install:
	@echo "=== 安装前清理 ==="
	-@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@# 注销用户级旧 bundle 的 LaunchServices 注册（防止列表残留）
	@if [ -d "$(BUNDLE_PATH)" ]; then \
		echo "注销并删除用户级旧 bundle: $(BUNDLE_PATH)"; \
		"$(LSREGISTER)" -u "$(BUNDLE_PATH)" 2>/dev/null || true; \
		rm -rf "$(BUNDLE_PATH)"; \
	fi
	@# 注销并删除系统级旧 bundle（DMG 安装器可能装在此处，需 sudo）
	@if [ -d "$(SYSTEM_BUNDLE_PATH)" ]; then \
		echo "发现系统级旧 bundle，尝试注销: $(SYSTEM_BUNDLE_PATH)"; \
		"$(LSREGISTER)" -u "$(SYSTEM_BUNDLE_PATH)" 2>/dev/null || true; \
		sudo rm -rf "$(SYSTEM_BUNDLE_PATH)" 2>/dev/null || \
			echo "  （需要 sudo 权限，若未删除请手动执行: sudo rm -rf \"$(SYSTEM_BUNDLE_PATH)\"）"; \
	fi
	@# 清除废纸篓中所有历史 LOInputMethod 副本（含 .app / 目录 / .pkg）
	@find "$(HOME)/.Trash" -maxdepth 1 -name "$(APP_NAME)*" -exec rm -rf {} + 2>/dev/null || true
	@echo "清理完成。"

## 安装到输入法目录（仅基础安装，不含 librime）
install: pre-install build fetch-dict
	@echo "安装 $(APP_NAME)..."
	@mkdir -p "$(BUNDLE_PATH)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_PATH)/Contents/Resources/rime"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(BUNDLE_PATH)/Contents/MacOS/$(APP_NAME)"
	@cp LOInputMethod/Info.plist "$(BUNDLE_PATH)/Contents/Info.plist"
	@cp LOInputMethod/Resources/AppIcon.icns "$(BUNDLE_PATH)/Contents/Resources/AppIcon.icns"
	@cp LOInputMethod/Resources/InfoPlist.strings "$(BUNDLE_PATH)/Contents/Resources/InfoPlist.strings"
	@cp -r LOInputMethod/Resources/rime/* "$(BUNDLE_PATH)/Contents/Resources/rime/"
	@cp -r LOInputMethod/Resources/zh-Hans.lproj "$(BUNDLE_PATH)/Contents/Resources/"
	@cp -r LOInputMethod/Resources/en.lproj "$(BUNDLE_PATH)/Contents/Resources/"
	@# 重新 ad-hoc 签名整个 bundle，封住 Info.plist/Resources（Sealed Resources），
	@# 并固定签名 Identifier = bundle id，确保 TCC 辅助功能授权稳定不丢失
	@# （未签名/ad-hoc 仅签二进制时，TCC 无法可靠绑定身份，每次重装授权失效）
	@codesign --force --deep --options runtime \
		--identifier "$(BUNDLE_ID)" \
		-s - "$(BUNDLE_PATH)"
	@# 强制注册到 LaunchServices，确保输入法列表只显示一项
	@"$(LSREGISTER)" -f "$(BUNDLE_PATH)" 2>/dev/null || true
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
	@cp LOInputMethod/Resources/AppIcon.icns "$(BUNDLE_PATH)/Contents/Resources/AppIcon.icns"
	@cp LOInputMethod/Resources/InfoPlist.strings "$(BUNDLE_PATH)/Contents/Resources/InfoPlist.strings"
	@cp -r LOInputMethod/Resources/rime/* "$(BUNDLE_PATH)/Contents/Resources/rime/"
	@cp -r LOInputMethod/Resources/zh-Hans.lproj "$(BUNDLE_PATH)/Contents/Resources/"
	@cp -r LOInputMethod/Resources/en.lproj "$(BUNDLE_PATH)/Contents/Resources/"
	@bash scripts/build-librime.sh
	@# 重新 ad-hoc 签名整个 bundle（封住 Info.plist/Resources，固定 Identifier=bundle id），
	@# 确保 TCC 辅助功能授权稳定（详见 install 目标注释）
	@codesign --force --deep --options runtime \
		--identifier "$(BUNDLE_ID)" \
		-s - "$(BUNDLE_PATH)"
	@# 强制注册到 LaunchServices，确保输入法列表只显示一项
	@"$(LSREGISTER)" -f "$(BUNDLE_PATH)" 2>/dev/null || true
	@# 清理用户 Rime 旧构建产物，强制重新编译新词典
	@rm -f "$(HOME)/Library/Rime/build/luna_pinyin.table.bin" \
	       "$(HOME)/Library/Rime/build/luna_pinyin.prism.bin" 2>/dev/null || true
	@echo "安装完成。请在系统设置中添加语境输入法。"

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
	@# 同时清理废纸篓残留
	@find "$(HOME)/.Trash" -maxdepth 1 -name "$(APP_NAME)*" -exec rm -rf {} + 2>/dev/null || true
	@killall TextInputMenuAgent 2>/dev/null || true
	@echo "已卸载 $(APP_NAME)。"

## 一键打包发布：构建输入法 + 安装器，生成 .dmg 安装镜像
## 产物：dist/语境输入法-<版本>.dmg，用户下载后双击安装器即可一键安装到系统
package:
	@bash scripts/package.sh
