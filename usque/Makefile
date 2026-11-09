# SPDX-License-Identifier: MIT
#
# Copyright (C) 2026 kenzok8

include $(TOPDIR)/rules.mk

PKG_NAME:=usque
PKG_VERSION:=4.2.1
PKG_RELEASE:=3

# Select the upstream binary that matches the 32-bit ARM CPU generation.
ifeq ($(ARCH),x86_64)
  USQUE_ARCH:=amd64
  USQUE_HASH:=4117e20695078af9c11edecd1a826c009bbc7ea0b7f64458612b4198910bc313
else ifeq ($(ARCH),aarch64)
  USQUE_ARCH:=arm64
  USQUE_HASH:=c88b061c2a567f30813d7505637d1fb6fe7ec5898b5b61fd05122409fa5ad925
else ifeq ($(ARCH),arm)
ifneq ($(filter cortex-a% armv7%,$(CPU_TYPE)),)
  USQUE_ARCH:=armv7
  USQUE_HASH:=5e0025f6298d3822ef13b85960fc7c5845f8510e1ddd088ea87ea0f00d39cc88
else ifneq ($(filter arm1176jzf-s arm1136jf-s,$(CPU_TYPE)),)
  USQUE_ARCH:=armv6
  USQUE_HASH:=089763d3a6a3dc1c15cccc87110fdfbf5b90031d667e248aed453032c310f0d0
else
  USQUE_ARCH:=armv5
  USQUE_HASH:=2954d4cb1927c954e47fb45c876fa47d262b745f0c8253808a3a5c9f5b5e799a
endif
else ifeq ($(ARCH),mips)
  USQUE_ARCH:=mips
  USQUE_HASH:=6c125f6679e0549df18e69eab5208278426c00f802aa9733ac6f52b941796ec9
else ifeq ($(ARCH),mipsel)
  USQUE_ARCH:=mipsle
  USQUE_HASH:=2e313c8eb34d36c29d61627f16503cf293209fcfb405e8516d9c95137da3771f
else ifeq ($(ARCH),mips64)
  USQUE_ARCH:=mips64
  USQUE_HASH:=59e65094f81f8a4fbe9bbdc6d3b4b99ef15cbe38793c9530f0bdd4223b432546
else ifeq ($(ARCH),mips64el)
  USQUE_ARCH:=mips64le
  USQUE_HASH:=20b3fa8ab1f7cc5dd99ea9106deddbd6c52a5bbe89385bcf21b090f4aad4ccd8
endif

PKG_SOURCE:=usque_$(PKG_VERSION)_linux_$(USQUE_ARCH).zip
# 第二行是传输兜底：CI 里同一份资产被并发下载时 GitHub 会返回 403/404，
# 镜像只负责搬运，完整性仍由 PKG_HASH 校验。
PKG_SOURCE_URL:=https://github.com/Diniboy1123/usque/releases/download/v$(PKG_VERSION)/ \
	https://ghfast.top/https://github.com/Diniboy1123/usque/releases/download/v$(PKG_VERSION)/
PKG_HASH:=$(USQUE_HASH)

PKG_LICENSE:=MIT GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE.md LICENSE.runtime
PKG_MAINTAINER:=kenzok8

include $(INCLUDE_DIR)/package.mk

define Package/usque
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Cloudflare WARP MASQUE client
  URL:=https://github.com/Diniboy1123/usque
  DEPENDS:=@(x86_64||aarch64||arm||mips||mipsel||mips64||mips64el) +kmod-tun +ip-full +ca-bundle +jsonfilter +firewall4 +curl +flock +ubus +coreutils-timeout
endef

define Package/usque/description
  Usque is an unofficial Cloudflare WARP client that speaks MASQUE.
  This package runs the upstream 4.2.1 binary and can expose SOCKS5 or a TUN device.
  TUN does not replace the router default route.
endef

define Package/usque/conffiles
/etc/config/usque
/etc/usque/config.json
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	unzip -q -o -d $(PKG_BUILD_DIR) $(DL_DIR)/$(PKG_SOURCE)
	$(CP) $(CURDIR)/LICENSE $(PKG_BUILD_DIR)/LICENSE.runtime
endef

define Build/Compile
endef

define Package/usque/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/usque $(1)/usr/bin/usque

	$(INSTALL_DIR) $(1)/usr/share/usque
	printf '%s\n' 'v$(PKG_VERSION)' > $(1)/usr/share/usque/version

	$(INSTALL_DIR) $(1)/usr/share/licenses/usque
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE.md $(1)/usr/share/licenses/usque/LICENSE.md
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE.runtime $(1)/usr/share/licenses/usque/LICENSE.runtime

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/usque.config $(1)/etc/config/usque

	$(INSTALL_DIR) $(1)/etc/usque
	chmod 0700 $(1)/etc/usque

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/usque.init $(1)/etc/init.d/usque

	$(INSTALL_DIR) $(1)/usr/share/usque
	$(INSTALL_BIN) $(CURDIR)/files/lib.sh $(1)/usr/share/usque/lib.sh
	$(INSTALL_BIN) $(CURDIR)/files/down.sh $(1)/usr/share/usque/down.sh
	$(INSTALL_BIN) $(CURDIR)/files/fw.sh $(1)/usr/share/usque/fw.sh
	$(INSTALL_BIN) $(CURDIR)/files/dns.sh $(1)/usr/share/usque/dns.sh
	$(INSTALL_BIN) $(CURDIR)/files/register.sh $(1)/usr/share/usque/register.sh
	$(INSTALL_BIN) $(CURDIR)/files/status.sh $(1)/usr/share/usque/status.sh
	$(INSTALL_BIN) $(CURDIR)/files/route.sh $(1)/usr/share/usque/route.sh
	$(INSTALL_BIN) $(CURDIR)/files/diagnostics.sh $(1)/usr/share/usque/diagnostics.sh
	$(INSTALL_BIN) $(CURDIR)/files/logs.sh $(1)/usr/share/usque/logs.sh
	$(INSTALL_BIN) $(CURDIR)/files/pkg-info.sh $(1)/usr/share/usque/pkg-info.sh
	$(INSTALL_BIN) $(CURDIR)/files/pkg-update.sh $(1)/usr/share/usque/pkg-update.sh
endef

define Package/usque/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ -x /etc/init.d/usque ] && /etc/init.d/usque stop
[ -x /etc/init.d/usque ] && /etc/init.d/usque disable
[ -x /usr/share/usque/fw.sh ] && /usr/share/usque/fw.sh off || true
exit 0
endef

$(eval $(call BuildPackage,usque))
