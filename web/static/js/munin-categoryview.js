/**
 * Javascript executed on munin-categoryview page
 */

$(document).ready(function() {
	var graphs = window.graphs = $('.graph');
	var services = $('.service');

	// Instantiate auto-refresh & dynazoom modal links components
	var autoRefresh = window.autoRefresh = graphs.autoRefresh();
	graphs.dynazoomModal();
	graphs.graph();

	addRefreshActionIcon(autoRefresh);

	// Prepare filter
	window.toolbar.prepareFilter('Filter graphs', function(val) {
		// Show or hide each service
		services.each(function() {
			var pluginInfos = $(this).attr('data-name');

			if (window.toolbar.filterMatches(val, pluginInfos))
				$(this).show();
			else
				$(this).hide();
		});
	});

	// Time range switch
	var url = window.location.pathname;
	var match = url.match(/\/(.*)-(.*)\.html(\?.*)?$/);
	var category = match[1],
		timeRange = match[2];

	var timeRangeSwitch = $('.timeRangeSwitch');
	timeRangeSwitch.find('li').click(function() {
		if ($(this).hasClass('selected'))
			return;

		// Update "selected" attribute
		$(this).parent().find('li').removeClass('selected');
		$(this).addClass('selected');

		window.location.href = './' + category + '-' + $(this).text() + '.html';
	});

	// Set current time range
	timeRangeSwitch.find('li:contains(' + timeRange + ')').addClass('selected');

	// Init eventruler
	$(this).eventRuler();

	// Assign tab-indexes to elements
	$('.graphLink').each(function(index) {
		$(this).attr('tabindex', index+1);
	});
	removeTabIndexOutline();
});
