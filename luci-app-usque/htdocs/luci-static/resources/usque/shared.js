'use strict';
'require fs';
'require uci';
'require ui';
'require poll';
'require baseclass';

var errors = {
	account_missing: _('Register an account before starting Usque.'),
	account_invalid: _('The saved account is incomplete. Register again or restore a valid account.'),
	register_failed: _('Registration failed. Your previous account has been kept.'),
	register_busy: _('Another registration is in progress. Try again shortly.'),
	lock_busy: _('Another network change is in progress. Try again shortly.'),
	invalid_mode: _('Choose SOCKS5 or TUN mode.'),
	invalid_bind: _('The listen address is invalid.'),
	invalid_port: _('Choose a port between 1 and 65535.'),
	invalid_interface: _('The network device name is invalid.'),
	interface_conflict: _('The selected device is already used by another network.'),
	lan_missing: _('The selected LAN device does not exist.'),
	lan_zone_mismatch: _('The selected device is not in the firewall LAN zone.'),
	route_conflict: _('The policy route or packet mark is already in use.'),
	firewall_conflict: _('A firewall section with the same name belongs to another configuration.'),
	firewall_failed: _('The firewall could not be applied. Check the firewall configuration.'),
	dns_conflict: _(
		'Another configuration already uses the tunnel DNS settings. LAN IPv4 routing was rolled back.'
	),
	dns_failed: _('The tunnel DNS resolver could not start. LAN IPv4 routing was rolled back.'),
	route_failed: _('The tunnel route could not be applied.'),
	probe_failed: _('The connectivity test failed. The process may still be running.'),
	not_running: _('Start Usque before testing the connection.'),
	tun_missing: _('The TUN device is not ready yet.'),
	configuration_changed: _('Settings changed. Restart Usque to apply them.'),
	unknown: _('The operation failed. Check the service and network configuration.')
};

function readJSON(result) {
	if (!result || result.code !== 0 || !result.stdout) throw new Error('rpc_failed');
	var value = JSON.parse(result.stdout);
	if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('rpc_failed');
	return value;
}

function message(code) {
	var aliases = {
		service_not_running: 'not_running',
		route_not_ready: 'route_failed',
		service_changed: 'configuration_changed',
		invalid_response: 'probe_failed'
	};
	return errors[aliases[code] || code] || errors.unknown;
}

function notify(text, danger) {
	ui.addNotification(null, E('p', {}, text), danger ? 'danger' : 'info');
}

function setText(node, text) {
	if (node && node.textContent !== text) node.textContent = text;
}

function hostTheme() {
	var node = document.getElementById('maincontent') || document.body;
	while (node) {
		var color = getComputedStyle(node).backgroundColor;
		var rgb = /^rgba?\(/.test(color) && color.match(/[\d.]+/g);
		if (rgb && (rgb.length < 4 || +rgb[3] > 0.5))
			return +rgb[0] * 0.299 + +rgb[1] * 0.587 + +rgb[2] * 0.114 < 120 ? 'dark' : 'light';
		node = node.parentElement;
	}
	return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function init(action) {
	return fs.exec('/etc/init.d/usque', [action]).then(function (result) {
		if (!result || result.code !== 0) throw new Error('service_failed');
	});
}

function waitForService(running, attempt) {
	return fs
		.exec('/usr/share/usque/status.sh')
		.then(readJSON)
		.then(function (state) {
			if (state.running === running) return;
			if (state.error || (attempt || 0) >= 5) throw new Error(state.error || 'not_running');
			return new Promise(function (resolve) {
				window.setTimeout(resolve, 500);
			}).then(function () {
				return waitForService(running, (attempt || 0) + 1);
			});
		});
}

function readStatus() {
	return fs
		.exec('/usr/share/usque/status.sh')
		.then(readJSON)
		.catch(function () {
			return { unavailable: true };
		});
}

/* 四个页面共用同一套外壳，保证视觉和导航一致 */
function page(version, body) {
	return E('div', { class: 'usque-app', 'data-theme': hostTheme() }, [
		E('link', {
			rel: 'stylesheet',
			href: L.resource('view/usque/usque.css') + '?v=' + encodeURIComponent(version || 'development')
		}),
		E('header', { class: 'usque-header' }, [
			E('img', { src: '/luci-static/usque/logo.svg', width: '28', height: '28', alt: '' }),
			E('h2', {}, 'Usque')
		]),
		body
	]);
}

return baseclass.extend({
	errors: errors,
	readJSON: readJSON,
	message: message,
	notify: notify,
	setText: setText,
	hostTheme: hostTheme,
	init: init,
	waitForService: waitForService,
	readStatus: readStatus,
	poll: poll,
	page: page
});
