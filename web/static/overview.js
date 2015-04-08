/**
 * Overview specific code
 */

$(document).ready(function() {
	prepareFilter('Filter nodes', function(expr) {
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
			if (!filterMatches(expr, $(this).text()))
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
});
