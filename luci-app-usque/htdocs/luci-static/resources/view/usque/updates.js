'use strict';
'require view';
'require fs';
'require poll';
'require ui';
'require usque.shared as shared';

var FEED_SETUP = 'wget -qO- https://down.dllkids.xyz/openwrt-feed/openwrt-feed-setup.sh | sh';

function readInfo() {
	return fs
		.exec('/usr/share/usque/pkg-info.sh')
		.then(shared.readJSON)
		.catch(function () {
			return { unavailable: true, packages: [] };
		});
}

function readJob() {
	return fs
		.exec('/usr/share/usque/pkg-update.sh', ['log'])
		.then(shared.readJSON)
		.catch(function () {
			return { running: false, state: 'idle', log: [] };
		});
}

return view.extend({
	load: function () {
		return Promise.all([shared.readStatus(), readInfo(), readJob()]);
	},

	render: function (data) {
		var self = this;
		self.state = data[0];
		self.info = data[1];
		self.job = data[2];
		self.busy = false;

		self.table = E('div', { class: 'usque-pkg-table' });
		self.jobBox = E('pre', { class: 'usque-log' });
		self.jobState = E('p', { class: 'usque-hint' });
		self.feedHint = E('div', { class: 'usque-note' });

		self.upgradeButton = E(
			'button',
			{
				class: 'usque-button usque-button-primary',
				click: function () {
					var button = this;
					if (self.busy) return Promise.resolve();
					self.busy = true;
					button.classList.add('is-busy');
					return fs
						.exec('/usr/share/usque/pkg-update.sh', ['start'])
						.then(function (result) {
							if (!result || result.code !== 0) {
								shared.notify(
									result && (result.stdout || '').indexOf('busy') === 0
										? _('An upgrade is already running.')
										: _('The upgrade could not be started.'),
									true
								);
								return;
							}
							return self.refreshJob();
						})
						.finally(function () {
							self.busy = false;
							button.classList.remove('is-busy');
						});
				}
			},
			_('Upgrade now')
		);

		function updatable(info) {
			return (info.packages || []).filter(function (pkg) {
				return pkg.installed && pkg.latest && pkg.installed !== pkg.latest;
			});
		}

		function paintInfo() {
			var info = self.info || {};
			self.table.innerHTML = '';
			if (info.unavailable) {
				self.table.appendChild(E('p', { class: 'usque-hint' }, _('Could not read package versions.')));
				return;
			}
			self.table.appendChild(
				E('table', { class: 'usque-table' }, [
					E('thead', {}, [
						E('tr', {}, [
							E('th', {}, _('Package')),
							E('th', {}, _('Installed')),
							E('th', {}, _('In repository'))
						])
					]),
					E(
						'tbody',
						{},
						(info.packages || []).map(function (pkg) {
							var state = !pkg.installed
								? _('Not installed')
								: !pkg.latest
									? _('Not in repository')
									: pkg.installed === pkg.latest
										? _('Up to date')
										: _('Update available');
							return E('tr', {}, [
								E('td', {}, [E('strong', {}, pkg.name), E('span', { class: 'usque-hint' }, ' · ' + state)]),
								E('td', {}, pkg.installed || '-'),
								E('td', {}, pkg.latest || '-')
							]);
						})
					)
				])
			);
			self.upgradeButton.disabled = !info.feed || updatable(info).length === 0 || self.job.running;

			self.feedHint.innerHTML = '';
			if (!info.feed) {
				self.feedHint.appendChild(
					E('div', {}, [
						E('h3', {}, _('No package source configured')),
						E(
							'p',
							{},
							_(
								'This page only sees what the local package manager has. Add the kenzok8 feed first, then reload this page.'
							)
						),
						E('code', { class: 'usque-code' }, FEED_SETUP)
					])
				);
			} else if ((info.packages || []).every(function (pkg) { return !pkg.latest; })) {
				self.feedHint.appendChild(
					E('p', {}, _('The source is configured but has no release of these packages yet.'))
				);
			}
		}

		function paintJob() {
			var job = self.job || {};
			self.jobBox.textContent = (job.log || []).length
				? job.log.join('\n')
				: _('Nothing has been upgraded from this page yet.');
			self.jobState.textContent = job.running
				? _('Upgrade running. This page refreshes while it works.')
				: job.state && job.state.indexOf('failed') === 0
					? _('The last upgrade failed. The log above shows why.')
					: job.state === 'done'
						? _('The last upgrade finished.')
						: '';
		}

		self.refreshJob = function () {
			return readJob().then(function (job) {
				self.job = job;
				paintJob();
				if (!job.running) return readInfo().then(function (info) {
					self.info = info;
					paintInfo();
				});
			});
		};

		var body = E('div', { class: 'usque-grid' }, [
			E('section', { class: 'usque-card' }, [
				E('div', { class: 'usque-card-head' }, [
					E('div', {}, [
						E('h3', {}, _('Package versions')),
						E('p', {}, _('Compared against the package source configured on this router.'))
					]),
					self.upgradeButton
				]),
				self.table,
				self.feedHint
			]),
			E('section', { class: 'usque-card' }, [E('h3', {}, _('Upgrade log')), self.jobState, self.jobBox]),
			E('section', { class: 'usque-card' }, [
				E('h3', {}, _('How updates work')),
				E('ul', { class: 'usque-list' }, [
					E('li', {}, _('Updates come from the kenzok8 package feed, not from GitHub.')),
					E('li', {}, _('Upgrading stops the service, replaces the packages and starts it again if it was enabled.')),
					E('li', {}, _('A freshly published version needs a feed sync before it shows up here.')),
					E('li', {}, _('Credentials in /etc/usque/config.json are not touched by upgrades.'))
				])
			])
		]);

		paintInfo();
		paintJob();
		poll.add(function () {
			return self.refreshJob();
		}, 5);

		return shared.page(self.state.ui_version, body);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
