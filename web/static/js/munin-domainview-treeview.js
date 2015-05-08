/**
 * Domainview treeview
 */

$(document).ready(function() {
	// Init treeview
	var toggles = $('.toggle');

	// All toggles are expanded
	toggles.attr('data-expanded', 'true');

	// Attach toggle event
	toggles.click(function() {
		toggle($(this));
	});
});

function toggle(toggleButton) {
	if (toggleButton.attr('data-expanded') == 'true') { // Reduce it
		toggleButton.parent().next().hide();

		toggleButton.attr('data-expanded', 'false');
	} else { // Expand it
		toggleButton.parent().next().show();

		toggleButton.attr('data-expanded', 'true');
	}
}

function expandAll() {
	// Expand each reduced toggles
	$('[data-expanded=false]').each(function() {
		toggle($(this));
	});
}

function reduceAll() {
	// Reduce each reduced toggles
	$('[data-expanded=true]').each(function() {
		toggle($(this));
	});
}
