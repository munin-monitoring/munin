/**
 * Comparison specific code
 */


$(document).ready(function() {
	var content = $('#content');
	var graphs = window.graphs = $('.graph');
	var trs = $('tr');

	// Instantiate auto-refresh & dynazoom modal links components
	var autoRefresh = graphs.autoRefresh();
	graphs.dynazoomModal();
	graphs.graph();

	addRefreshActionIcon(autoRefresh);

	// Tabs
	var tabs = $(this).tabs();

	// Prepare filter
	window.toolbar.prepareFilter('Filter graphs', function(val) {
		if (val.length == 0)
			tabs.showTabs();
		else
			tabs.hideTabs();

		trs.each(function() {
			var serviceName = $(this).data('servicename');
			var serviceTitle = $(this).data('servicetitle');

			if (window.toolbar.filterMatches(val, serviceName) || window.toolbar.filterMatches(val, serviceTitle)) {
				$(this).show();
			}
			else {
				$(this).hide();
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
		$('table[data-category]').each(function() {
			if ($(this).find('tr:visible').length == 0)
				$(this).prev().hide();
			else
				$(this).prev().show();
		});

		if (val.length == 0) {
			// Remove display CSS property to category names (h3)
			// to let tabs decide if they should be shown or not
			$('h3').css('display', '');
		}
	});

	// Groups switch
	$('.switchable[data-switch="header"]').list('header', {
		list: $('.switchable_content[data-switch="header"]')
	});

	// Time range switch
	var timeRangeSwitch = $('.timeRangeSwitch');
	timeRangeSwitch.find('li').click(function() {
		if ($(this).hasClass('selected'))
			return;

		// Update "selected" attribute
		$(this).parent().find('li').removeClass('selected');
		$(this).addClass('selected');

		window.location.href = './comparison-' + $(this).text() + '.html?cat=' + $('ul.tabs').find('.active').text();
	});

	// Set current time range
	var url = window.location.href;
	var timeRange = url.match(/comparison-(.*)\.html/)[1];
	timeRangeSwitch.find('li:contains(' + timeRange + ')').addClass('selected');

	// Init eventruler
	$(this).eventRuler();
});
