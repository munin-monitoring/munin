/**
 * Overview specific code
 */

// Hide sparklines on error (if the load plugin isn't available for example)
// We have to register it as soon as possible or the sparklines may have loaded
//  before we could handle the error
$('.sparkline').on('error', function() {
	$(this).parent().hide(); // Hide container
});

$(document).ready(function() {
	window.toolbar.prepareFilter('Filter nodes', function(expr) {
		var groupView = $('.groupview');

		var groups = groupView.children();
		groups.show();
		var hosts = $('.host');
		hosts.parent().show();
		var noResult = $('#overview-search-noresult');
		noResult.hide();

		if (expr == '')
			return;

		// Simple filter from name
		hosts.each(function() {
			if (!window.toolbar.filterMatches(expr, $(this).text()))
				$(this).parent().hide();
		});

		// Hide groups if there isn't any remaining children shown
		groups.each(function() { // each li
			if ($(this).find('ul > li:visible').length == 0)
				$(this).hide();
		});

		// Check if there is still something shown
		if (groupView.find('>:visible').length == 0)
			noResult.show();
	});

	// Sparklines tooltips
	var spkCnters = $('.overview-sparkline');
	spkCnters.each(function() {
		$(this).after('<div class="tooltip">' + $(this).find('img.sparkline').attr('alt') + '</div>');
	});
	prepareTooltips(spkCnters, function(sparkline) {
		return sparkline.next();
	});

	// Sparklines auto-refresh
	var sparklines = $('.sparkline');
	sparklines.after('<img src="/static/img/loading.gif" class="graph_loading" style="display:none" />');
	$(this).autoRefresh({
		graphsSelector: '.sparkline'
	});
});
