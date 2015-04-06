/**
 * Nodeview - Time range switch
 * Quickly change time range for every graph in the column
 */

$(document).ready(function() {
    $('.timeRangeSwitch').find('ul > li').click(function() {
        if ($(this).hasClass('disabled') || $(this).hasClass('selected'))
            return;

        var currentRange = $(this).parent().find('.selected').first().text();
        var newRange = $(this).text();

        // Image may still be loading (if the user is really quick on switching time range)
        // Let's remove any loading image if necessary
        $('.graph_loading[data-timerange="' + currentRange + '"]').remove();

        // Remove "selected" attribute
        $(this).parent().find('li').removeClass('selected');

        // Add "selected" class to this
        $(this).addClass('selected');

        // Add "disabled" class to the other time range switch
        var thisRSIndex = $(this).parent().parent().index();
        var otherRS = $($('.timeRangeSwitch')[thisRSIndex == 1 ? 0 : 1]);
        var otherLi = otherRS.find('li');
        otherLi.removeClass('disabled');
        otherLi.each(function() {
            if ($(this).text() == newRange)
                $(this).addClass('disabled');
        });



        // Replace src attribute of current column (all images that matches current range)
        // => contains "-day." for day (don't force extension since there can be pngs/svgs)
        var srcSelector = '-' + currentRange + '.';
        var newSrcSelector = '-' + newRange + '.';

        var images = $("img[src*='" + srcSelector + "']");
        images.each(function() {
            var currentImg = $(this).attr('src');
            $(this).attr('src', currentImg.replace(srcSelector, newSrcSelector));
        });

        // Show a loading spinner on each changed image
        images.css('opacity', '0.7');
        var r_path = $('#r_path').val();
        images.after('<img src="' + r_path + '/static/loading.gif" class="graph_loading" data-timerange="' + newRange + '" />');

        // Detect image load
        images.on('load', function() {
            $(this).css('opacity', '1');
            // Remove loading image
            $(this).next().remove();
        });
    });
});
