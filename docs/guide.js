'use strict';
(function () {
	var key = 'openwrt-usque-docs-theme';
	var theme = null;
	try {
		theme = localStorage.getItem(key);
	} catch (e) {}
	if (theme !== 'light' && theme !== 'dark')
		theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
	document.documentElement.dataset.theme = theme;
	document.querySelector('#theme').addEventListener('click', function () {
		theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
		document.documentElement.dataset.theme = theme;
		try {
			localStorage.setItem(key, theme);
		} catch (e) {}
	});
	document.querySelector('#menu').addEventListener('click', function () {
		var open = document.querySelector('#navigation').classList.toggle('open');
		this.setAttribute('aria-expanded', String(open));
	});
	document.querySelector('#search').addEventListener('input', function () {
		var query = this.value.trim().toLocaleLowerCase();
		var visible = 0;
		document.querySelectorAll('main section').forEach(function (section) {
			var match = !query || section.textContent.toLocaleLowerCase().indexOf(query) !== -1;
			section.hidden = !match;
			var link = document.querySelector('nav a[href="#' + section.id + '"]');
			if (link) link.hidden = !match;
			if (match) visible++;
		});
		document.querySelector('#no-results').hidden = visible > 0;
	});
})();
