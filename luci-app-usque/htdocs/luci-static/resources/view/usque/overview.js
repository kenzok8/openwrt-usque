'use strict';
'require view';
'require fs';
'require ui';
'require usque.shared as shared';

return view.extend({
	load: function () {
		return shared.readStatus();
	},

	refresh: function () {
		var self = this;
		return shared.readStatus().then(function (state) {
			if (self.probe && (!state.running || self.probe.pid !== state.pid)) self.invalidateProbe();
			self.state = state;
			self.drawStatus();
		});
	},

	runProbe: function (button) {
		var self = this;
		return self.runAction(button || self.testButton, function () {
			self.resetProbe(_('Testing through Usque…'));
			return fs
				.exec('/usr/share/usque/diagnostics.sh')
				.then(shared.readJSON)
				.then(function (result) {
					if (!result.targets || !result.targets.length)
						throw new Error(result.error || 'probe_failed');
					self.probe = { pid: self.state.pid };
					self.paintProbe(result);
				})
				.catch(function (error) {
					self.resetProbe(shared.message(error && error.message));
					self.probeRows.warp.dataset.state = 'fail';
				});
		});
	},

	invalidateProbe: function () {
		this.probe = null;
		this.resetProbe(_('No connectivity test yet. Process status alone does not confirm WARP access.'));
	},

	// 信号格按延迟分档，阈值按这条线路的实测（1.1–4.4 秒）定
	probeLevel: function (ok, ms) {
		if (!ok) return 0;
		if (!ms || ms <= 1500) return 4;
		if (ms <= 3000) return 3;
		if (ms <= 6000) return 2;
		return 1;
	},

	resetProbe: function (note) {
		var self = this;
		if (self.probeRows) {
			Object.keys(self.probeRows).forEach(function (key) {
				var row = self.probeRows[key];
				row.dataset.state = 'idle';
				row.dataset.level = '0';
				row.querySelector('.usque-probe-value').textContent = _('Not tested');
			});
		}
		if (self.probeNote) self.probeNote.textContent = note || '';
	},

	paintProbe: function (result) {
		var self = this,
			time = new Date().toLocaleTimeString();
		(result.targets || []).forEach(function (target) {
			var row = self.probeRows[target.id];
			if (!row) return;
			var ok = !!target.ok;
			row.dataset.state = ok ? 'pass' : 'fail';
			row.dataset.level = String(self.probeLevel(ok, target.ms));
			var value;
			if (target.id === 'warp')
				value =
					target.code === 'plus'
						? 'WARP+'
						: target.code === 'on'
							? _('WARP')
							: target.code === 'off'
								? _('Not through WARP')
								: _('Failed');
			else value = ok ? (target.ms ? target.ms + ' ms' : _('OK')) : _('Failed');
			row.querySelector('.usque-probe-value').textContent = value;
		});
		var passed = result.warp === 'on' || result.warp === 'plus';
		var note = result.error
			? shared.message(result.error)
			: passed
				? _('WARP access verified by this test.')
				: _('This test did not go through WARP.');
		self.probeNote.textContent = note + ' · ' + time;
	},

	drawStatus: function () {
		if (!this.statusNode) return;
		var st = this.state || {};
		var tone = 'idle',
			title = _('Ready when you are'),
			detail = _('Register a WARP account, then enable the service below.');
		if (st.unavailable) {
			tone = 'error';
			title = _('Status unavailable');
			detail = _('Could not read service status. Refresh to try again.');
		} else if (
			st.error &&
			st.error !== 'none' &&
			st.error !== 'not_registered' &&
			st.error !== 'account_missing' &&
			st.error !== 'service_stopped'
		) {
			tone = 'error';
			title = _('Needs attention');
			detail = shared.message(st.error);
		} else if (st.running) {
			tone = 'running';
			title = _('Usque is running');
			detail = st.enabled
				? st.mode === 'tun'
					? _('The process is running. Test the connection to verify WARP access.')
					: _('Your local SOCKS5 endpoint is ready for a connectivity test.')
				: _('Running now, but not set to start at boot. A reboot stops it.');
		} else if (st.registered) {
			title = _('Account ready');
			detail = st.enabled
				? _('The service is enabled but is not running.')
				: _('Turn on “Enable and start at boot” and apply to start it.');
		}
		this.statusNode.dataset.tone = tone;
		shared.setText(this.statusNode.querySelector('[data-status="title"]'), title);
		shared.setText(this.statusNode.querySelector('[data-status="detail"]'), detail);
		shared.setText(
			this.statusNode.querySelector('[data-status="account"]'),
			st.unavailable ? _('Unknown') : st.registered ? _('Registered') : _('Not registered')
		);
		shared.setText(
			this.statusNode.querySelector('[data-status="scope"]'),
			st.unavailable
				? _('Unknown')
				: st.mode === 'tun'
					? st.lan_routing
						? st.route_ready
							? st.dns_routing
								? _('LAN IPv4 + DNS')
								: _('LAN IPv4 protected')
							: _('Waiting for TUN')
						: _('Manual TUN access')
					: _('Local SOCKS5')
		);
		shared.setText(this.statusNode.querySelector('[data-status="version"]'), st.version || '-');
		this.restartButton.disabled = this.busy || !st.running;
		// 手动启停只影响本次运行，和开机自启无关，所以不看 enabled
		this.powerButton.disabled = this.busy || st.unavailable || !st.registered;
		this.powerButton.textContent = st.running ? _('Stop service') : _('Start service');
		this.testButton.disabled = this.busy || !st.running;
		this.registerButton.disabled = this.busy || st.unavailable;
		this.registerButton.textContent = st.registered ? _('Replace account') : _('Register account');
	},

	runAction: function (button, action) {
		var self = this;
		if (self.busy) return Promise.resolve();
		self.busy = true;
		button.classList.add('is-busy');
		self.drawStatus();
		return Promise.resolve()
			.then(action)
			.catch(function (error) {
				shared.notify(
					shared.errors[error && error.message] ||
						_('The operation failed. Your settings are kept. Refresh the status and try again.'),
					true
				);
			})
			.finally(function () {
				self.busy = false;
				button.classList.remove('is-busy');
				return self.refresh();
			});
	},

	register: function () {
		var self = this,
			replacing = !!self.state.registered;
		var consent = E('input', { type: 'checkbox', id: 'usque-consent' });
		var confirm = E(
			'button',
			{ class: 'usque-button usque-button-primary', disabled: true },
			replacing ? _('Replace account') : _('Register account')
		);
		consent.addEventListener('change', function () {
			confirm.disabled = !consent.checked;
		});
		confirm.addEventListener('click', function (ev) {
			ev.preventDefault();
			if (!consent.checked) return;
			ui.hideModal();
			return self.runAction(self.registerButton, function () {
				return fs.exec('/usr/share/usque/register.sh', replacing ? ['force'] : []).then(function (result) {
					if (!result || result.code !== 0) {
						var busy = result && (result.stdout || '').trim() === 'busy';
						shared.notify(
							busy
								? shared.message('register_busy')
								: result && result.code === 2
									? _('An account already exists. Refresh the page before replacing it.')
									: _('Registration failed. Your previous account has been kept.'),
							true
						);
						return;
					}
					self.invalidateProbe();
					shared.notify(_('Account saved.'));
					if (self.state.running) return shared.init('restart');
				});
			});
		});
		ui.showModal(replacing ? _('Replace account') : _('Register a WARP account'), [
			E('div', { class: 'usque-app usque-modal', 'data-theme': shared.hostTheme() }, [
				E(
					'p',
					{},
					replacing
						? _(
								'A new account replaces the saved account only after registration succeeds. Failure keeps the current account.'
							)
						: _('This requests a free WARP account from Cloudflare and stores its credentials on this router.')
				),
				E('label', { class: 'usque-consent', for: 'usque-consent' }, [
					consent,
					E('span', {}, [
						_('I accept the Cloudflare terms for this registration.'),
						' ',
						E(
							'a',
							{
								href: 'https://www.cloudflare.com/application/terms/',
								target: '_blank',
								rel: 'noopener noreferrer'
							},
							_('Read terms')
						)
					])
				]),
				E('div', { class: 'usque-modal-actions' }, [
					E('button', { class: 'usque-button', click: ui.hideModal }, _('Cancel')),
					confirm
				])
			])
		]);
	},

	render: function (state) {
		var self = this;
		self.state = state;
		self.busy = false;

		self.registerButton = E(
			'button',
			{
				class: 'usque-button usque-button-link',
				click: function () {
					self.register();
				}
			},
			_('Register account')
		);
		self.restartButton = E(
			'button',
			{
				class: 'usque-button',
				click: function () {
					return self.runAction(this, function () {
						self.invalidateProbe();
						return shared.init('restart');
					});
				}
			},
			_('Restart')
		);
		self.powerButton = E(
			'button',
			{
				class: 'usque-button',
				click: function () {
					var button = this;
					if (!self.state.running)
						return self.runAction(button, function () {
							return shared.init('start');
						});
					ui.showModal(_('Stop Usque?'), [
						E('div', { class: 'usque-app usque-modal', 'data-theme': shared.hostTheme() }, [
							E(
								'p',
								{},
								_(
									'Stopping removes Usque routing and restores the original IPv4 route. The boot setting is unchanged.'
								)
							),
							E('div', { class: 'usque-modal-actions' }, [
								E('button', { class: 'usque-button', click: ui.hideModal }, _('Cancel')),
								E(
									'button',
									{
										class: 'usque-button usque-button-danger',
										click: function () {
											ui.hideModal();
											return self.runAction(button, function () {
												self.invalidateProbe();
												return shared.init('stop');
											});
										}
									},
									_('Stop service')
								)
							])
						])
					]);
				}
			},
			_('Start service')
		);
		function probeRow(id, label) {
			return E('div', { class: 'usque-probe-row', 'data-id': id, 'data-state': 'idle' }, [
				E('span', { class: 'usque-probe-icon', 'data-id': id, 'aria-hidden': 'true' }),
				E('span', { class: 'usque-probe-name' }, label),
				E('span', { class: 'usque-bars', 'aria-hidden': 'true' }, [E('i', {}), E('i', {}), E('i', {}), E('i', {})]),
				E('span', { class: 'usque-probe-value' }, _('Not tested'))
			]);
		}

		self.probeRows = {
			warp: probeRow('warp', _('Cloudflare WARP')),
			youtube: probeRow('youtube', 'YouTube'),
			domestic: probeRow('domestic', _('ByteDance (direct)'))
		};
		self.probeNote = E(
			'p',
			{ class: 'usque-hint usque-probe-note', role: 'status', 'aria-live': 'polite' },
			_('Run the test to check all three paths separately.')
		);
		self.probePanel = E('div', { class: 'usque-probe' }, [
			self.probeRows.warp,
			self.probeRows.youtube,
			self.probeRows.domestic
		]);
		self.testButton = E(
			'button',
			{
				class: 'usque-button usque-button-primary',
				click: function () {
					return self.runProbe(this);
				}
			},
			_('Test connection')
		);
		self.statusNode = E('section', { class: 'usque-status', 'aria-live': 'polite' }, [
			E('div', { class: 'usque-status-main' }, [
				E('span', { class: 'usque-dot', 'aria-hidden': 'true' }),
				E('div', {}, [E('h3', { 'data-status': 'title' }), E('p', { 'data-status': 'detail' })])
			]),
			E('dl', { class: 'usque-facts' }, [
				E('div', {}, [E('dt', {}, _('Account')), E('dd', { 'data-status': 'account' })]),
				E('div', {}, [E('dt', {}, _('Traffic scope')), E('dd', { 'data-status': 'scope' })]),
				E('div', {}, [E('dt', {}, _('Core version')), E('dd', { 'data-status': 'version' })])
			]),
			E('div', { class: 'usque-actions' }, [self.powerButton, self.restartButton, self.registerButton])
		]);

		var body = E('div', { class: 'usque-grid' }, [
			self.statusNode,
			E('section', { class: 'usque-card' }, [
				self.probePanel,
				E('div', { class: 'usque-probe-foot' }, [self.probeNote, self.testButton])
			])
		]);

		var root = shared.page(self.state.ui_version, body);
		self.drawStatus();
		shared.poll.add(function () {
			return self.refresh();
		}, 5);
		// 服务在跑但本次打开还没测过，自动验一次，省得用户以为没数据
		if (self.state && self.state.running && !self.probe) self.runProbe();
		return root;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
