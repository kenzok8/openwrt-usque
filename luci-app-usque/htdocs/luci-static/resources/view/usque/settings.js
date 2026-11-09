'use strict';
'require view';
'require form';
'require uci';
'require ui';
'require usque.shared as shared';

return view.extend({
	load: function () {
		return Promise.all([uci.load('usque'), shared.readStatus()]);
	},

	render: function (data) {
		var self = this;
		self.state = data[1];
		self.busy = false;

		var m = new form.Map('usque');
		var s = m.section(form.NamedSection, 'main', 'usque');
		s.anonymous = true;
		s.addremove = false;

		var o = s.option(form.Flag, 'enabled', _('Enable and start at boot'));
		o.rmempty = false;
		o.description = _('Applying starts the service now and keeps it on after a reboot.');
		o = s.option(form.ListValue, 'mode', _('Operating mode'));
		o.value('socks', _('SOCKS5 · local proxy'));
		o.value('tun', _('TUN · network interface'));
		o.rmempty = false;
		o = s.option(form.Value, 'bind', _('Listen address'));
		o.retain = true;
		o.depends('mode', 'socks');
		o.datatype = 'ipaddr';
		o.rmempty = false;
		o.description = _('127.0.0.1 stays on this router. Other addresses expose an unauthenticated proxy.');
		o = s.option(form.Value, 'port', _('Listen port'));
		o.retain = true;
		o.depends('mode', 'socks');
		o.datatype = 'port';
		o.rmempty = false;
		o = s.option(form.Value, 'ifname', _('TUN device'));
		o.retain = true;
		o.depends('mode', 'tun');
		o.rmempty = false;
		o.validate = self.validateInterface;
		o = s.option(form.Flag, 'route_lan', _('Route LAN IPv4'));
		o.retain = true;
		o.depends('mode', 'tun');
		o.rmempty = false;
		o.description = _('Only forwarded IPv4 from this device goes through TUN. IPv6 stays as is.');
		o = s.option(form.Value, 'lan_device', _('LAN device'));
		o.retain = true;
		o.depends({ mode: 'tun', route_lan: '1' });
		o.rmempty = false;
		o.validate = self.validateInterface;
		o.description = _('Use a device in the firewall LAN zone, normally br-lan.');
		o = s.option(form.Flag, 'route_dns', _('Route LAN DNS into the tunnel'));
		o.retain = true;
		o.depends({ mode: 'tun', route_lan: '1' });
		o.rmempty = false;
		o.description = _('Only this device uses the resolver inside the tunnel.');
		o = s.option(form.Value, 'endpoint', _('Endpoint address'));
		o.datatype = 'ip4addr';
		o.placeholder = '162.159.198.2';
		o.rmempty = false;
		o.description = _('Leave empty to use the address stored in the account. Change it when the default endpoint is unreachable.');
		o = s.option(form.Value, 'device_name', _('Registration device name'));
		o.rmempty = false;
		o.description = _('Apply before registering. Changing it does not rename an existing account.');
		o.validate = function (section, value) {
			return /^[A-Za-z0-9._-]{1,32}$/.test(value || '')
				? true
				: _('Use 1–32 letters, numbers, dots, underscores or hyphens.');
		};

		self.map = m;
		return m.render().then(function (formNode) {
			var body = E('div', { class: 'usque-grid' }, [
				E('section', { class: 'usque-card usque-settings' }, [formNode])
			]);
			return shared.page(self.state.ui_version, body);
		});
	},

	validateInterface: function (section, value) {
		return /^[A-Za-z][A-Za-z0-9._-]{0,14}$/.test(value || '')
			? true
			: _('Start with a letter and use at most 15 letters, numbers, dots, underscores or hyphens.');
	},

	handleSaveApply: function (ev, mode) {
		var self = this;
		if (self.busy) return Promise.resolve();
		self.busy = true;
		return self
			.handleSave(ev)
			.then(function () {
				return ui.changes.apply(mode === '0');
			})
			.then(function () {
				var enabled = uci.get('usque', 'main', 'enabled') === '1';
				return shared
					.init(enabled ? 'enable' : 'disable')
					.then(function () {
						return shared.init(enabled ? 'restart' : 'stop');
					})
					.then(function () {
						return shared.waitForService(enabled);
					})
					.then(function () {
						shared.notify(_('Settings applied.'));
					});
			})
			.catch(function (error) {
				shared.notify(
					shared.errors[error && error.message] ||
						_('The operation failed. Your settings are kept. Refresh the status and try again.'),
					true
				);
			})
			.finally(function () {
				self.busy = false;
			});
	}
});
