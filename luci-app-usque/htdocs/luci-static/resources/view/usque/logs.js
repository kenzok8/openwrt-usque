'use strict';
'require view';
'require fs';
'require poll';
'require ui';
'require usque.shared as shared';

return view.extend({
	load: function () {
		return Promise.all([shared.readStatus(), this.fetchLines()]);
	},

	fetchLines: function () {
		return fs
			.exec('/usr/share/usque/logs.sh', ['300'])
			.then(shared.readJSON)
			.then(function (data) {
				return Array.isArray(data.lines) ? data.lines : [];
			})
			.catch(function () {
				return [];
			});
	},

	render: function (data) {
		var self = this;
		self.state = data[0];
		self.lines = data[1];
		self.auto = false;

		self.output = E('pre', { class: 'usque-log' });
		self.count = E('span', { class: 'usque-eyebrow' });

		function paint() {
			self.output.textContent = self.lines.length
				? self.lines.join('\n')
				: _('No usque entries in the system log yet.');
			self.count.textContent = String(self.lines.length);
		}

		var autoBox = E('input', { type: 'checkbox', id: 'usque-log-auto' });
		autoBox.addEventListener('change', function () {
			self.auto = autoBox.checked;
		});

		var refreshButton = E(
			'button',
			{
				class: 'usque-button usque-button-primary',
				click: function () {
					var button = this;
					button.classList.add('is-busy');
					return self
						.fetchLines()
						.then(function (lines) {
							self.lines = lines;
							paint();
						})
						.finally(function () {
							button.classList.remove('is-busy');
						});
				}
			},
			_('Refresh')
		);

		var body = E('div', { class: 'usque-grid' }, [
			E('section', { class: 'usque-card' }, [
				E('div', { class: 'usque-card-head' }, [
					E('span', { class: 'usque-mono-count' }, [E('span', {}, self.count), ' ', _('lines shown')]),
					E('div', { class: 'usque-actions' }, [
						E('label', { class: 'usque-inline-check', for: 'usque-log-auto' }, [
							autoBox,
							E('span', {}, _('Auto refresh'))
						]),
						refreshButton
					])
				]),
				self.output
			])
		]);

		paint();
		poll.add(function () {
			if (!self.auto) return Promise.resolve();
			return self.fetchLines().then(function (lines) {
				self.lines = lines;
				paint();
			});
		}, 5);

		return shared.page(self.state.ui_version, body);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
