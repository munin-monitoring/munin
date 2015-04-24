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
		updateFilterInURL();
	});

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

	// There may be a 'filter' GET parameter in URL: let's apply it
	var qs = new Querystring();
	if (qs.contains('filter')) {
		var filter = $('#filter');
		filter.val(qs.get('filter'));
		// Manually trigger the keyUp event on filter input
		filter.keyup();
	}
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


/* Tooltips */
/**
 * Prepares tooltips for current page
 * @param hoverableElements Each element that triggers tooltip fadeIn
 * @param getTooltip Function that returns tooltip for 1st parameter element
 */
function prepareTooltips(hoverableElements, getTooltip) {
    hoverableElements.mouseenter(function() {
        var tooltip = getTooltip($(this));
        var bottom = $(this).position().top + $(this).outerHeight(true);
        tooltip.css('top', bottom);

        if (!tooltip.is('[data-dontsetleft]')) {
            var left = $(this).position().left + $(this).outerWidth() / 2;
            tooltip.css('left', left);
        }
        tooltip.fadeIn(100);
    });
    hoverableElements.mouseleave(function() {
        getTooltip($(this)).fadeOut(100);
    });
}
