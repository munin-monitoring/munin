/**
 * Main UI script
 *  This file is included in every page
 */

$(document).ready(function() {
	// Navigation toggle on tablets
	$('#navToggle').click(function() {
		var nav = $('#nav');

		if ($(this).hasClass('expanded')) {
			$(this).removeClass('expanded');
			nav.hide();
		} else {
			$(this).addClass('expanded');
			nav.show();
		}
	});

	// Hide filter input, will be shown
	// 	when implemented using prepareFilter
	$('#filter').parent().hide();
});

/**
 * Called by each page to setup header filter
 * @param placeholder Input placeholder
 * @param onFilterChange Called each time the input text changes
 */
function prepareFilter(placeholder, onFilterChange) {
	var input = $('#filter');

	// Show the filter input
	input.parent().show();

	// Set placeholder
	input.attr('placeholder', placeholder);

	input.on('keyup', function() {
		var val = $(this).val();

		if (val != '')
			$('#cancelFilter').show();
		else
			$('#cancelFilter').hide();

		onFilterChange(val);
	});

	input.on('focusout', updateFilterInURL);

	$('#cancelFilter').click(function() {
		input.val('');
		$(this).hide();
		onFilterChange('');
		updateFilterInURL();
	});

	// Register ESC key: same action as cancel filter
	$(document).keyup(function(e) {
		var filterInput = $('#filter');
		if (e.keyCode == 27 && filterInput.is(':focus') && filterInput.val().length > 0)
			$('#cancelFilter').click();
	});
}

/**
 * Returns true whenever a result matches the filter expression
 * @param filterExpr User-typed expression
 * @param result Candidate
 */
function filterMatches(filterExpr, result) {
	return sanitizeFilter(result).indexOf(sanitizeFilter(filterExpr)) != -1;
}

/**
 * Transforms a string to weaken filter
 * 	(= get more filter results)
 * @param filterExpr
 */
function sanitizeFilter(filterExpr) {
	return filterExpr.toLowerCase().trim();
}

/**
 * Adds or updates current filter as GET parameter in URL
 */
function updateFilterInURL() {
	// Put the filter query in the URL (to keep it when refreshing the page)
	var query = $('#filter').val();

	// Add it in current URL parameters list
	var qs = new Querystring();
	qs.set('filter', query);

	// Replace URL
	var url = $.param(qs.params);
	var pageName = $(document).find("title").text();
	window.history.replaceState('', pageName, '?' + url);
}
