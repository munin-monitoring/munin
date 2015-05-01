/**
 * Nodeview tabs
 */

var content,
    tabsContainer,
    tabs,
    activeTab;

$(document).ready(function() {
    content = $('#content');
    tabsContainer = $('.tabs');
    tabs = tabsContainer.find('li');
    activeTab = tabs.first();

    activeTab.addClass('active');

    tabs.click(function() {
        activeTab = $(this);

        tabs.removeClass('active');
        activeTab.addClass('active');

        // Hide all categories
        $('div[data-category]').hide();
        $('div[data-category="' + activeTab.text() + '"]').show();
    });

    enableTabs();
});

/**
 * Called on filter search begins
 */
function enableTabs() {
    if (content.attr('data-tabs') == 'true')
        return;

    content.attr('data-tabs', 'true');

    // Only show activeTab
    $('div[data-category]').not('[data-category="' + activeTab.text() + '"]').hide();
}

/**
 * Called on filter search ends
 */
function disableTabs() {
    if (content.attr('data-tabs') == 'false')
        return;

    content.attr('data-tabs', 'false');

    // Show back every hidden tabs
    $('div[data-category]').show();
}
