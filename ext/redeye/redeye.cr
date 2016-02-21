%pkg-config gdk-pixbuf-2.0
%include gdk-pixbuf/gdk-pixbuf.h

%option gtk=no
%map VALUE > GdkPixbuf* : GDK_PIXBUF(RVAL2GOBJ(%%))
%map GdkPixbuf* > VALUE : GOBJ2RVAL(GDK_PIXBUF(%%))
%map unref_pixbuf > VALUE : unref_pixbuf((%%))

%{

#define assert(x) if (!(x)) { rb_raise(rb_eRuntimeError, "Assertion: '%s' failed.", #x); }

typedef struct {
	char red,green,blue;
} rgb_t;

typedef struct {
	int minX, maxX, minY, maxY;
	int width, height;
	int noPixels, mergeWith;
} region_info;

typedef struct {
	struct {
		int minX, maxX, minY, maxY;
		int width, height;
	} area;
	struct {
		int *data;
		region_info *region;
		int len, size;
	} regions;
	int *mask;
	GdkPixbuf *pixbuf, *preview;
} redeyeop_t;

#define MIN_RED_VAL 20

static inline VALUE
unref_pixbuf(GdkPixbuf *pixbuf)
{
	volatile VALUE pb = Qnil;

	pb = GOBJ2RVAL(pixbuf);

	g_object_unref(pixbuf);

	return pb;
}

static void identify_possible_redeye_pixels(redeyeop_t *op,
	double green_sensitivity, double blue_sensitivity,
	int min_red_val)
{
		guchar *data = gdk_pixbuf_get_pixels(op->pixbuf);
		int rowstride = gdk_pixbuf_get_rowstride(op->pixbuf);
		int pixWidth = gdk_pixbuf_get_has_alpha(op->pixbuf) ? 4 : 3;

		int y, ry = 0, x, rx = 0;
		for ( y = op->area.minY; y < op->area.maxY; y++ )
		{
		   guchar *thisLine = data + (rowstride * y);
			guchar *pixel;

			pixel = thisLine + (op->area.minX * pixWidth);
			rx = 0;

		   for ( x = op->area.minX; x < op->area.maxX; x++ )
		   {

		   	int r,g,b;

		   	r = pixel[0];
		   	g = pixel[1];
		   	b = pixel[2];

			   gboolean threshMet;

			   threshMet = (((double)r) > (green_sensitivity * (double)g)) &&
			   		(((double)r) > (blue_sensitivity * (double)b)) &&
			   		(r > min_red_val);

			   if(threshMet)
			      op->mask[ rx + ry ] = r;
			   else
			      op->mask[ rx + ry ] = 0; /* MEMZERO should have done its job ? */

			   pixel += pixWidth;
			   rx ++;
			}

		   ry += op->area.width;
		}
}


inline int group_at(redeyeop_t *op, int px, int py)
{
	int index, region;

	if (px < 0 || py < 0)
		return 0;

	index = px + ( py * op->area.width );

	if (index < 0)
		return 0;
	if (index > (op->area.width * op->area.height))
		return 0;

	region = op->regions.data[ index ];
	if (region > 0) {
		if (op->regions.region[ region ].mergeWith) {
			return op->regions.region[ region ].mergeWith;
		} else {
			return region;
		}
	} else {
		return 0;
	}
}

#define group_for(x,y) group_at(op, x, y)

static void identify_blob_groupings(redeyeop_t *op)
{
	volatile int next_blob_id = 1, blob_id, y, x;


	for( y = 0; y < op->area.height; y++ )
	{
		for ( x = 0; x < op->area.width; x++ )
		{
			if (op->mask[ x + (y * op->area.width) ] > 0) {
				gboolean existing = FALSE;
				int sx, sy, group = 0;
				// Target pixel is true
				blob_id = 0;

				for (sy = y; sy >= y - 1; sy --) {
					sx = (sy == y) ? x : x + 1;
					for (; sx >= (x - 1); sx --) {
					/*if ((sx >= x) && (sy >= y))
							goto blob_scan_done;*/

						if (sx >= 0 && sy >= 0)
							group = group_for(sx, sy);

						if (group) {
							existing = TRUE;
							if (blob_id) {
								int target = MIN(blob_id, group);
								int from  = MAX(blob_id, group);

								if (op->regions.region[target].mergeWith > 0) {
									// Already merged
									target = op->regions.region[target].mergeWith;
								}
								op->regions.region[from].mergeWith = target;

								// Merge blob_id & group
							}
							blob_id = group;
						}
					}
				}

				if (blob_id == 0)
				{ // Allocate new group
					blob_id = next_blob_id;
					op->regions.region[blob_id].minX = x;
					op->regions.region[blob_id].maxX = x;
					op->regions.region[blob_id].minY = y;
					op->regions.region[blob_id].maxY = y;
					op->regions.region[blob_id].width = 1;
					op->regions.region[blob_id].height = 1;
					op->regions.region[blob_id].noPixels = 1;
					op->regions.region[blob_id].mergeWith = 0;

					next_blob_id ++;
					op->regions.len  = next_blob_id;

					if (next_blob_id >= op->regions.size) {
						int extra, new_size;

						/*
						 * Realloc in increasingly large chunks to reduce memory fragmentation
						 */
						extra = op->regions.size;
						new_size = op->regions.size + extra;

						REALLOC_N(op->regions.region, region_info, new_size);

						op->regions.size = new_size;
					}
				}

				if (existing)
				{
					op->regions.region[blob_id].minX = MIN(x, op->regions.region[blob_id].minX);
					op->regions.region[blob_id].maxX = MAX(x, op->regions.region[blob_id].maxX);
					op->regions.region[blob_id].minY = MIN(y, op->regions.region[blob_id].minY);
					op->regions.region[blob_id].maxY = MAX(y, op->regions.region[blob_id].maxY);
					op->regions.region[blob_id].width = op->regions.region[blob_id].maxX -
																op->regions.region[blob_id].minX + 1;
					op->regions.region[blob_id].height =  op->regions.region[blob_id].maxY -
																op->regions.region[blob_id].minY + 1;
					op->regions.region[blob_id].noPixels ++;
				}

				op->regions.data[ x + (y * op->area.width) ] = blob_id;
			}
		}
	}
	/*FILE *fp = fopen("regions.txt","w");*/
	for (y = 0; y < op->area.height; y++) {
		for (x = 0; x < op->area.width; x++) {
			int g = group_at(op, x, y); // Returns the merged group...
			op->regions.data[ x + (y * op->area.width) ] = g;
			/*
			if (op->regions.len <= 0xf || 1)
			{
			if (g == 0)
				fprintf(fp, " ");
			else
				fprintf(fp, "%x", g);
			}
			else
			{
			if (g == 0)
				fprintf(fp, "  ");
			else
				fprintf(fp, "%x ", g);
			}*/
		}
		/*fprintf(fp, "\n");*/
	}
	/*fclose(fp);*/
}
#define NO_REGIONS_DEFAULT 20
#define MIN_ID 1


static redeyeop_t *new_redeye(void)
{
	 redeyeop_t *ptr = ALLOC(redeyeop_t);
	 MEMZERO(ptr, redeyeop_t,  1);
	 return ptr;
}

static void free_redeye(redeyeop_t *ptr)
{
	if (ptr->mask)
		free(ptr->mask);
	if (ptr->regions.data);
		free(ptr->regions.data);
	if (ptr->regions.region);
		free(ptr->regions.region);
	if (ptr->pixbuf)
		g_object_unref(ptr->pixbuf);
	if (ptr->preview)
		g_object_unref(ptr->preview);
	free(ptr);
}


inline gboolean in_region(redeyeop_t *op, int x, int y, int blob_id)
{
	int index;

	if ( x < op->area.minX || x > op->area.maxX ||
		  y < op->area.minY || y > op->area.maxY )
		return FALSE;

	index = (x - op->area.minX) + ((y - op->area.minY) * op->area.width);

	return op->regions.data[index] == blob_id;
}

inline double alpha_level_for_pixel(redeyeop_t *op, int x, int y, int blob_id)
{
	int j = 0, c = 0, xm, ym;

	if (in_region(op, x, y, blob_id))
		return 1.0;

	for ( xm = -2; xm <= 2; xm++ )
	{
		for ( ym = -2; ym <= 2; ym ++ )
		{
			c ++;
			if (xm == 0 && ym == 0)
				continue;
			if (in_region(op, x+xm, y+ym, blob_id))
				j ++;
		}
	}

	return ((double)j)/((double)c);
}

inline char col(double val)
{
	if (val < 0) return 0;
	if (val > 255) return 255;
	return val;

}

static GdkPixbuf *redeye_preview(redeyeop_t *op, gboolean reset)
{
	int width, height;
	width  = op->area.width;
	height = op->area.height;

	if (width + op->area.minX > gdk_pixbuf_get_width(op->pixbuf)) {
		width = gdk_pixbuf_get_width(op->pixbuf) - op->area.minX;
	}
	if (height + op->area.minY > gdk_pixbuf_get_height(op->pixbuf)) {
		height = gdk_pixbuf_get_height(op->pixbuf) - op->area.minY;
	}

	if ( op->preview == NULL )
	{
		GdkPixbuf *sub = NULL;
		sub = gdk_pixbuf_new_subpixbuf(op->pixbuf, op->area.minX, op->area.minY,
							width, height);

		op->preview = gdk_pixbuf_copy(sub);
		g_object_unref(sub);
	} else if (reset) {
		gdk_pixbuf_copy_area(op->pixbuf, op->area.minX, op->area.minY,
					width, height, op->preview, 0, 0);
	}

	return op->preview;
}

static void desaturate_blob(redeyeop_t *op, int blob_id)
{
	int y, x;
	int minX, minY, maxX, maxY;

	minY = MAX(0, op->area.minY + op->regions.region[blob_id].minY - 1);
	maxY = MIN(op->area.maxY + op->regions.region[blob_id].maxY + 1,
		gdk_pixbuf_get_height(op->pixbuf)-1);
	minX = MAX(0, op->area.minX + op->regions.region[blob_id].minX - 1);
	maxX = MIN(op->area.maxX + op->regions.region[blob_id].maxX + 1,
		gdk_pixbuf_get_width(op->pixbuf)-1);

	guchar *data = gdk_pixbuf_get_pixels(op->pixbuf);
	int rowstride = gdk_pixbuf_get_rowstride(op->pixbuf);
	int pixWidth = gdk_pixbuf_get_has_alpha(op->pixbuf) ? 4 : 3;

	for ( y = minY; y <= maxY; y++ )
	{
	   guchar *thisLine = data + (rowstride * y);
		guchar *pixel;

		pixel = thisLine + (minX * pixWidth);

	   for ( x = minX; x <= maxX; x++ )
	   {

		 	double alpha = alpha_level_for_pixel(op, x, y, blob_id);
		 	int r,g,b,grey;

		  	r = pixel[0];
		  	g = pixel[1];
		  	b = pixel[2];

		 	if (alpha > 0)
		 	{
		   	grey = alpha * ((double)( 5 * (double)r + 60 * (double)g + 30 * (double)b)) / 100.0 +
						(1 - alpha) * r;

		 		pixel[0] = col((grey * alpha) + (1-alpha) * r);
		 		pixel[1] = col((grey * alpha) + (1-alpha) * g);
		 		pixel[2] = col((grey * alpha) + (1-alpha) * b);
		 	}

		 	pixel += pixWidth;
		}
	}

}

static void highlight_blob(redeyeop_t *op, int blob_id, int colour)
{
	int y, x;
	int minX, minY, maxX, maxY;
	int hr, hg, hb;

	hr = (colour >> 16) & 0xff;
	hg = (colour >> 8) & 0xff;
	hb = (colour) & 0xff;

	minY = MAX(0, op->area.minY - 1);
	maxY = MIN(op->area.maxY + 1, gdk_pixbuf_get_height(op->pixbuf)-1);
	minX = MAX(0, op->area.minX - 1);
	maxX = MIN(op->area.maxX + 1, gdk_pixbuf_get_width(op->pixbuf)-1);

	guchar *data = gdk_pixbuf_get_pixels(op->pixbuf);
	int rowstride = gdk_pixbuf_get_rowstride(op->pixbuf);
	int pixWidth = gdk_pixbuf_get_has_alpha(op->pixbuf) ? 4 : 3;

	for ( y = minY; y <= maxY; y++ )
	{
	   guchar *thisLine = data + (rowstride * y);
		guchar *pixel;

		pixel = thisLine + (minX * pixWidth);

	   for ( x = minX; x <= maxX; x++ )
	   {

		 	double alpha = alpha_level_for_pixel(op, x, y, blob_id);
		 	int r,g,b;

		  	r = (pixel[0]);
		  	g = (pixel[1]);
		  	b = (pixel[2]);


		 	if (alpha > 0)
		 	{

		  		pixel[0] = col((1-alpha) * r + (alpha * hr));
		  		pixel[1] = col((1-alpha) * g + (alpha * hg));
		  		pixel[2] = col((1-alpha) * b + (alpha * hb));
		 	}

		 	pixel += pixWidth;
		}
	}

}


static void preview_blob(redeyeop_t *op, int blob_id, int colour, gboolean reset_preview)
{
	int y, x;
	int minX, minY, maxX, maxY;
	int hr, hg, hb;

	redeye_preview(op, reset_preview);

	hr = (colour >> 16) & 0xff;
	hg = (colour >> 8) & 0xff;
	hb = (colour) & 0xff;

	minY = 0;
	maxY = gdk_pixbuf_get_height(op->preview)-1;
	minX = 0;
	maxX = gdk_pixbuf_get_width(op->preview)-1;

	guchar *data = gdk_pixbuf_get_pixels(op->preview);
	int rowstride = gdk_pixbuf_get_rowstride(op->preview);
	int pixWidth = gdk_pixbuf_get_has_alpha(op->preview) ? 4 : 3;

	for ( y = minY; y <= maxY; y++ )
	{
	   guchar *thisLine = data + (rowstride * y);
		guchar *pixel;

		pixel = thisLine + (minX * pixWidth);

	   for ( x = minX; x <= maxX; x++ )
	   {

		 	double alpha = alpha_level_for_pixel(op, x + op->area.minX, y + op->area.minY, blob_id);
		 	int r,g,b;

		  	r = (pixel[0]);
		  	g = (pixel[1]);
		  	b = (pixel[2]);


		 	if (alpha > 0)
		 	{

		  		pixel[0] = col((1-alpha) * r + (alpha * hr));
		  		pixel[1] = col((1-alpha) * g + (alpha * hg));
		  		pixel[2] = col((1-alpha) * b + (alpha * hb));
		 	}

		 	pixel += pixWidth;
		}
	}

}

%}

class RedEye
	struct Region(op, id, minX, minY, maxX, maxY, width, height, noPixels)
		def double:ratio
			int width,height;
			double min,max,ratio;
			width = <{VALUE>int:rb_struct_getmember(self, rb_intern("width"))}>;
			height = <{VALUE>int:rb_struct_getmember(self, rb_intern("height"))}>;
			min = (double)MIN(width,height);
			max = (double)MAX(width,height);
			ratio = (min / max);
			return ratio;
		end
		def double:density
			int noPixels, width, height;
			double density;

			noPixels = <{VALUE>int:rb_struct_getmember(self, rb_intern("noPixels"))}>;
			width = <{VALUE>int:rb_struct_getmember(self, rb_intern("width"))}>;
			height = <{VALUE>int:rb_struct_getmember(self, rb_intern("height"))}>;
			density = ((double)noPixels / (double)(width * height));

			return density;
		end
		def gboolean:squareish?(double min_ratio = 0.5, double min_density = 0.5)
			int noPixels, width, height;
			double min, max, ratio, density;

			noPixels = <{VALUE>int:rb_struct_getmember(self, rb_intern("noPixels"))}>;
			width = <{VALUE>int:rb_struct_getmember(self, rb_intern("width"))}>;
			height = <{VALUE>int:rb_struct_getmember(self, rb_intern("height"))}>;

			min = (double)MIN(width,height);
			max = (double)MAX(width,height);
			ratio = (min / max);

			density = ((double)noPixels / (double)(width * height));

			return ((ratio >= min_ratio) && (density > min_density));
		end
	end

	def __alloc__
		return Data_Wrap_Struct(self, NULL, free_redeye, new_redeye());
	end

	def initialize(GdkPixbuf *pixbuf, int minX, int minY, int maxX, int maxY)
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		op->pixbuf = pixbuf;
		op->preview = NULL;
		g_object_ref(op->pixbuf);

		op->area.minX = minX;
		op->area.maxX = maxX;
		op->area.minY = minY;
		op->area.maxY = maxY;
		op->area.width = maxX - minX + 1;
		op->area.height = maxY - minY + 1;

		assert(op->pixbuf != NULL);
		assert(op->area.maxX <= gdk_pixbuf_get_width(op->pixbuf));
		assert(op->area.minX >= 0);
		assert(op->area.minX < op->area.maxX);
		assert(op->area.maxY <= gdk_pixbuf_get_height(op->pixbuf));
		assert(op->area.minY >= 0);
		assert(op->area.minY < op->area.maxY);


		op->mask = ALLOC_N(int, op->area.width * op->area.height);

		op->regions.data = ALLOC_N(int, op->area.width * op->area.height);

		op->regions.region = ALLOC_N(region_info, NO_REGIONS_DEFAULT);

		op->regions.len = 0;
		op->regions.size = NO_REGIONS_DEFAULT;
	end

	def identify_blobs(double green_sensitivity=2.0, double blue_sensitivity=0.0, int min_red_val = MIN_RED_VAL)
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		MEMZERO(op->mask, int,  op->area.width * op->area.height);
		MEMZERO(op->regions.data,  int, op->area.width * op->area.height);

		identify_possible_redeye_pixels(op, green_sensitivity, blue_sensitivity, min_red_val);
		identify_blob_groupings(op);

		volatile VALUE ary = rb_ary_new2(op->regions.len);
		int i;
		for (i = MIN_ID; i < op->regions.len; i++) {
			region_info *r = &op->regions.region[i];
			/* Ignore CCD noise */
			if (r->noPixels < 2)
				continue;
			rb_ary_push(ary, rb_struct_new(structRegion, self, INT2NUM(i),
				INT2NUM(r->minX), INT2NUM(r->minY), INT2NUM(r->maxX), INT2NUM(r->maxY),
				INT2NUM(r->width), INT2NUM(r->height), INT2NUM(r->noPixels)));
		}
		return ary;
	end

	def correct_blob(int blob_id)
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		if (op->regions.len <= blob_id)
			rb_raise(rb_eIndexError, "Only %i blobs in region - %i is invalid", op->regions.len, blob_id);


		desaturate_blob(op, blob_id);
	end

	def highlight_blob(int blob_id, int col = 0x00ff00)
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		if (op->regions.len <= blob_id)
			rb_raise(rb_eIndexError, "Only %i blobs in region - %i is invalid", op->regions.len, blob_id);

		highlight_blob(op, blob_id, col);
	end

	def GdkPixbuf*:preview_blob(int blob_id, int col = 0x00ff00, gboolean reset_preview = TRUE)
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		if (op->regions.len <= blob_id)
			rb_raise(rb_eIndexError, "Only %i blobs in region - %i is invalid", op->regions.len, blob_id);

		preview_blob(op, blob_id, col, reset_preview);

		return op->preview;
	end
	def GdkPixbuf*:preview
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		return redeye_preview(op, FALSE);
	end
	def GdkPixbuf*:pixbuf
		redeyeop_t *op;

		Data_Get_Struct(self, redeyeop_t, op);

		return op->pixbuf;
	end
end

