/**
 * Graphs auto-refresh
 */
(function($, window) {
	var AutoRefresh = function(elems, options) {
		this.graphs = $(elems);
		this.options = options;
		this.metadata = this.graphs.data('autorefresh-options');
	};

	AutoRefresh.prototype = {
		defaults: { },

		init: function() {
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			if (getCookie('graph_autoRefresh', true))
				this.start();

			return this;
		},

		start: function() {
			if (this.intervalId !== undefined)
				return;

			var that = this;

			// Start timer
			this.intervalId = setInterval(function() {
				that.refreshAll.call(that);
			}, 5*60*1000);
		},

		stop: function() {
			if (this.intervalId === undefined)
				return;

			clearInterval(this.intervalId);
			this.intervalId = undefined;
		},

		refreshAll: function() {
			this.graphs.each(function() {
				$(this).data('graph').refresh();
			});
		}
	};

	AutoRefresh.defaults = AutoRefresh.prototype.defaults;

	$.fn.autoRefresh = function(options) {
		return new AutoRefresh(this, options).init();
	};

	window.AutoRefresh = AutoRefresh;
}(jQuery, window));
