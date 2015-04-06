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

        // Tell that the image is loading
        images.each(function() {
            setImageLoading($(this), true);
        });
    });

    // Keep it on top of window on scroll
    var timeRangeSwitchContainer = $('.timeRangeSwitchContainer');
    var header = $('#header');
    $(window).scroll(function() {
        if ($(this).scrollTop() > header.height())
            timeRangeSwitchContainer.addClass('timeRangeFixed');
        else
            timeRangeSwitchContainer.removeClass('timeRangeFixed');
    });
});
