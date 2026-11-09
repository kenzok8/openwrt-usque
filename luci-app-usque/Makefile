# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 kenzok8

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-usque
PKG_VERSION:=2026.11.08
PKG_RELEASE:=4
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
PKG_BUILD_DEPENDS:=luci-base/host
PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=kenzok8

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-usque
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Usque
  DEPENDS:=+usque +luci-base
  PKGARCH:=all
  URL:=https://github.com/Diniboy1123/usque
  MAINTAINER:=kenzok8
endef

define Package/luci-app-usque/description
  LuCI web interface for the Usque WARP client.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	po2lmo ./po/zh-cn/usque.po $(PKG_BUILD_DIR)/usque.zh-cn.lmo
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-usque/install
	$(INSTALL_DIR) $(1)/usr/share/luci-app-usque
	printf '%s\n' '$(PKG_VERSION)-r$(PKG_RELEASE)' > $(1)/usr/share/luci-app-usque/version
	$(INSTALL_DIR) $(1)/usr/share/licenses/luci-app-usque
	$(INSTALL_DATA) ./LICENSE $(1)/usr/share/licenses/luci-app-usque/LICENSE
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-usque.json $(1)/usr/share/luci/menu.d/luci-app-usque.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-usque.json $(1)/usr/share/rpcd/acl.d/luci-app-usque.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/usque
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/usque/overview.js $(1)/www/luci-static/resources/view/usque/overview.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/usque/settings.js $(1)/www/luci-static/resources/view/usque/settings.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/usque/logs.js $(1)/www/luci-static/resources/view/usque/logs.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/usque/updates.js $(1)/www/luci-static/resources/view/usque/updates.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/usque/usque.css $(1)/www/luci-static/resources/view/usque/usque.css
	$(INSTALL_DIR) $(1)/www/luci-static/resources/usque
	$(INSTALL_DATA) ./htdocs/luci-static/resources/usque/shared.js $(1)/www/luci-static/resources/usque/shared.js
	$(INSTALL_DIR) $(1)/www/luci-static/usque
	$(INSTALL_DATA) ./htdocs/luci-static/usque/logo.svg $(1)/www/luci-static/usque/logo.svg
	$(INSTALL_DATA) ./htdocs/luci-static/usque/logo.png $(1)/www/luci-static/usque/logo.png

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/usque.zh-cn.lmo $(1)/usr/lib/lua/luci/i18n/usque.zh-cn.lmo
endef

define Package/luci-app-usque/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
endef

define Package/luci-app-usque/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-modulecache
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-usque))
