/**
 * Javascript executed on munin-nodeview page
 */

var content,
	graphs,
	h4s,
	tabs;

$(document).ready(function() {
	content = $('#content');
	graphs = window.graphs = $('.graph');
	h4s = $('h4');
	tabs = $('.tabs').find('li');

	// Instantiate auto-refresh & dynazoom modal links components
	var autoRefresh = window.autoRefresh = graphs.autoRefresh();
	graphs.dynazoomModal();
	graphs.graph();

	addRefreshActionIcon(autoRefresh);

	var tabsComponent = $(this).tabs();

	// Prepare filter
	window.toolbar.prepareFilter('Filter graphs', function(val) {
		if (val.length == 0)
			tabsComponent.showTabs();
		else
			tabsComponent.hideTabs();

		graphs.each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (window.toolbar.filterMatches(val, pluginName) || window.toolbar.filterMatches(val, pluginId)) {
				$(this).parent().show();
				// Show plugin name
				h4s.filter(function() {
					return $(this).text() == pluginName;
				}).show();

				// Show next <br>
				if ($(this).parent().next()[0].tagName.toLowerCase() == 'br')
					$(this).parent().next().show();
			}
			else {
				$(this).parent().hide();
				// Hide plugin name
				h4s.filter(function() {
					return $(this).text() == pluginName;
				}).hide();

				// Hide next <br>
				if ($(this).parent().next()[0].tagName.toLowerCase() == 'br')
					$(this).parent().next().hide();
			}
		});

		// If tabs aren't enabled, they are used as anchors links
		if (content.attr('data-tabsenabled') == 'false') {
			tabs.each(function() {
				if (window.toolbar.filterMatches(val, $(this).text()))
					$(this).show();
				else
					$(this).hide();
			});
		}

		// Hide unnecessary categories names
		$('div[data-category]').each(function() {
			if ($(this).children(':visible').length == 0)
				$(this).prev().hide();
			else
				$(this).prev().show();
		});

		if (val.length == 0 // Empty filter
			&& content.attr('data-tabsenabled') == 'true' // Tabs enabled
			&& tabs.prevAll('.active').index() != 0 // Not "all"
		) {
			// Hide categories names
			$('h3').hide();
		}
	});


	// Back to top button
	var backToTop = $('#backToTop');
	var offset = 300;

	$(window).scroll(function() {
		if ($(this).scrollTop() > offset)
			backToTop.addClass('visible');
		else
			backToTop.removeClass('visible');
	});

	backToTop.click(function(e) {
		e.preventDefault();
		$('body, html').animate({
			scrollTop: 0
		}, 500);
	});

	// Node switch
	$('.switchable[data-switch="header"]').list('header', {
		list: $('.switchable_content[data-switch="header"]')
	});

	// Init eventruler
	$(this).eventRuler();

	// Assign tab-indexes to elements
	$('.tabs > li:visible, .graph').each(function(index) {
		$(this).attr('tabindex', index+1);
	});
});
