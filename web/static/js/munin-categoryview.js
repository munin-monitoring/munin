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
		graphs.each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (window.toolbar.filterMatches(val, pluginName) || window.toolbar.filterMatches(val, pluginId)) {
				$(this).parent().parent().show();
			}
			else {
				$(this).parent().parent().hide();
			}
		});

		// Hide/show categories names
		// We can't just use the ':visible' selector since parent
		//	may be hidden
		services.each(function() {
			//if ($(this).children('.node:visible').length == 0)

			services.each(function() {
				if ($(this).children().filter(function() {
						return $(this).css('display') == 'none';
					}).length > 0)
					$(this).hide();
				else
					$(this).show();
			});
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
	graphs.each(function(index) {
		$(this).attr('tabindex', index+1);
	});
});
