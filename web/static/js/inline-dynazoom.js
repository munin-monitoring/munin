/**
 * Adds a dynazoom icon on each graph
 */

$(document).ready(function() {
	var graphs = $('.graph');

	graphs.after('<img src="/static/img/icons/expand.png" class="dynazoomModalLink" />');
});
