/**
 * Javascript executed on munin-nodeview page
 * Please note that there is also nodeview-timerangeswitch.js
 */

$(document).ready(function() {
    // Append a loading <img> on each graph img
    var images = $('.graph');
    var r_path = $('#r_path').val();
    images.after('<img src="' + r_path + '/static/loading.gif" class="graph_loading" style="display:none" />');

    // Register on image load event to hide loading styles
    images.on('load', function() {
        setImageLoading($(this), false);
    });
});

/**
 * Tells UI that this specific image is loading (or not)
 *  (lowers opacity and shows loading spinner)
 */
function setImageLoading(imgDomElement, isLoading) {
    if (isLoading) {
        imgDomElement.css('opacity', '0.7');
        imgDomElement.next().show();
    } else {
        imgDomElement.css('opacity', '1');
        imgDomElement.next().hide();
    }
}
