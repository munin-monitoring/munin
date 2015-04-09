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

	$('#cancelFilter').click(function() {
		input.val('');
		$(this).hide();
		onFilterChange('');
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
