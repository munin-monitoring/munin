/**
 * Graph component
 */
(function($, window) {
	var TimeRanges = {
		Hour: 'hour',
		Day: 'day',
		Week: 'week',
		Month: 'month',
		Year: 'year'
	};

	var GraphFormats = {
		PNG: 'png',
		PNGx2: 'pngx2',
		SVG: 'svg'
	};

	var Graph = function(elem, options) {
		this.elem = $(elem);
		this.options = options;
	};

	Graph.prototype = {
		defaults: {

		},

		init: function() {
			this.settings = $.extend({}, this.defaults, this.options);

			// Detect graph timerange & graph format
			var fileName = this.elem.attr('src');
			var matches = fileName.match(/-(hour|day|week|month|year)\.(png|svg|pngx(?:[0-9]))(\?.*)?$/);

			this.timeRange = matches[1];
			this.graphExt = matches[2];
			this.params = matches.length >= 4 ? matches[3] : null;

			// Register load & error event to hide loading styles
			this.registerLoadingEvents('load error');

			// Append spinner
			this.loadingSpinner = $('<img />')
				.attr('src', '/static/img/loading.gif')
				.addClass('graph-loading')
				.css('display', 'none')
				.insertBefore(this.elem);

			return this;
		},

		setTimeRange: function(timeRange) {
			this.timeRange = timeRange;

			// Replace src attribute
			var fileName = this.elem.attr('src');
			this.elem.attr('src', this.generateURLName(fileName, this.timeRange, this.graphExt));

			return this;
		},

		setGraphExt: function(graphExt) {
			this.graphExt = graphExt;

			// Replace src attribute
			var fileName = this.elem.attr('src');
			this.elem.attr('src', this.generateURLName(fileName, this.timeRange, this.graphExt));

			return this;
		},

		refresh: function() {
			var src = this.elem.attr('src');

			// Replace timestamp in URL
			src = replaceUrlParam(src, 't', new Date().getTime());

			// Since we change the src attr, we have to reattach the error event
			this.registerLoadingEvents('error');

			this.elem.attr('src', src);
			this.setLoading(true);

			return this;
		},

		setLoading: function(isLoading) {
			if (isLoading) {
				this.elem.css('opacity', '0.7');
				this.loadingSpinner.show();
			} else {
				this.elem.css('opacity', '1');
				this.loadingSpinner.hide();
			}

			return this;
		},

		registerLoadingEvents: function(events) {
			var that = this;
			this.elem.on(events, function() {
				that.setLoading(false);
			});
		},

		generateURLName: function(url, timeRange, graphExt) {
			return url.replace(/-(hour|day|week|month|year)\.(png|svg|pngx(?:[0-9]))(\?.*)?$/, function(expr, oldTimeRange, oldGraphExt, parameters, i4) {
				var newUrl = '-' + timeRange + '.' + graphExt;
				return newUrl + (parameters != undefined ? parameters : '');
			});
		}
	};

	Graph.defaults = Graph.prototype.defaults;
	Graph.TimeRanges = TimeRanges;
	Graph.GraphFormats = GraphFormats;

	$.fn.graph = function(options) {
		return this.each(function() {
			if (!$(this).data('graph'))
				$(this).data('graph', new Graph(this, options).init());
		});
	};

	window.Graph = Graph;
}(jQuery, window));
