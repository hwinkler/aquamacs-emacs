/* Image support for the NeXT/Open/GNUstep and MacOSX window system.
   Copyright (C) 1989, 1992, 1993, 1994, 2005, 2006, 2008, 2009, 2010, 2011, 2012
     Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.  */

/*
Originally by Carl Edman
Updated by Christian Limpach (chris@nice.ch)
OpenStep/Rhapsody port by Scott Bender (sbender@harmony-ds.com)
MacOSX/Aqua port by Christophe de Dinechin (descubes@earthlink.net)
GNUstep port and post-20 update by Adrian Robert (arobert@cogsci.ucsd.edu)
*/

/* This should be the first include, as it may set up #defines affecting
   interpretation of even the system includes. */
#include "config.h"
#include <setjmp.h>

#include "lisp.h"
#include "dispextern.h"
#include "nsterm.h"
#include "frame.h"

extern Lisp_Object QCfile, QCdata;

/* call tracing */
#if 0
int image_trace_num = 0;
#define NSTRACE(x)        fprintf (stderr, "%s:%d: [%d] " #x "\n",         \
                                __FILE__, __LINE__, ++image_trace_num)
#else
#define NSTRACE(x)
#endif


/* ==========================================================================

   C interface.  This allows easy calling from C files.  We could just
   compile everything as Objective-C, but that might mean slower
   compilation and possible difficulties on some platforms..

   ========================================================================== */

void *
ns_image_from_XBM (unsigned char *bits, int width, int height)
{
  NSTRACE (ns_image_from_XBM);
  return [[EmacsImage alloc] initFromXBM: bits
                                   width: width height: height
                                    flip: YES];
}

void *
ns_image_for_XPM (int width, int height, int depth)
{
  NSTRACE (ns_image_for_XPM);
  return [[EmacsImage alloc] initForXPMWithDepth: depth
                                           width: width height: height];
}

void *
ns_image_from_file (Lisp_Object file)
{
  NSTRACE (ns_image_from_bitmap_file);
  return [EmacsImage allocInitFromFile: file];
}

int
ns_load_image (struct frame *f, struct image *img,
               Lisp_Object spec_file, Lisp_Object spec_data)
{
  NSTRACE (ns_load_image);

  EmacsImage *eImg;
  NSSize size;

  if (NILP (spec_data))
    {
      eImg = [EmacsImage allocInitFromFile: spec_file];
    }
  else
    {
      NSData *data = [NSData dataWithBytes: SDATA (spec_data)
			    length: SBYTES (spec_data)];
      eImg = [[EmacsImage alloc] initWithData: data];
      [eImg setPixmapData];
    }

  if (eImg == nil)
    {
      add_to_log ("Unable to load image %s", img->spec, Qnil);
      return 0;
    }

  /* Pixels = Points in Emacs world... */
  size = [eImg size];
  img->width = size.width;
  img->height = size.height;

  /* 4) set img->pixmap = emacsimage */
  img->pixmap = eImg;
  return 1;
}


int
ns_image_width (void *img)
{
  /*
  NSImageRep *imgRep;

  if ([(id)img respondsToSelector: @selector (bestRepresentationForRect:context:hints:)])
    {
      imgRep = [img bestRepresentationForRect: NSMakeRect(100,100,30,30)  context:nil hints: nil];

      if (imgRep)
	return [imgRep pixelsWide];
    }
  */
  return [(id)img size].width;
}

int
ns_image_height (void *img)
{
  /*
  NSImageRep *imgRep;

  if ([(id)img respondsToSelector: @selector (bestRepresentationForRect:context:hints:)])
    {
      imgRep = [img bestRepresentationForRect: NSMakeRect(100,100,30,30)  context:nil hints: nil];

      if (imgRep)
	return [imgRep pixelsHigh];
    }
  */
  return [(id)img size].height;
}

unsigned long
ns_get_pixel (void *img, int x, int y)
{
  return [(EmacsImage *)img getPixelAtX: x Y: y];
}

void
ns_put_pixel (void *img, int x, int y, unsigned long argb)
{
  unsigned char alpha = (argb >> 24) & 0xFF;
  if (alpha == 0)
    alpha = 0xFF;
  [(EmacsImage *)img setPixelAtX: x Y: y toRed: (argb >> 16) & 0xFF
   green: (argb >> 8) & 0xFF blue: (argb & 0xFF) alpha: alpha];
}

void
ns_set_alpha (void *img, int x, int y, unsigned char a)
{
  [(EmacsImage *)img setAlphaAtX: x Y: y to: a];
}


/* ==========================================================================

   Class supporting bitmaps and images of various sorts.

   ========================================================================== */

extern Lisp_Object Vns_true_dpi_images_filename_string;
/* defined in nsterm.m */


@implementation EmacsImage

static EmacsImage *ImageList = nil;

+ allocInitFromFile: (Lisp_Object)file
{
  EmacsImage *image;
  NSImageRep *imgRep;
  Lisp_Object found;

  #if 1
  image =  ImageList;
  /* look for an existing image of the same name */
  while (image != nil &&
	 // not all images seem to have names.
	 // The reason for this is unclear.
	 ([image name] == nil ||
	  [[image name] compare: [NSString stringWithUTF8String: SDATA (file)]]
	  != NSOrderedSame))
    image = [image imageListNext];
  if (image != nil)
    {
      [(EmacsImage *)image reference];
      return image;
    }
  #else
  // this variant uses the NS/Cocoa image store
  // it might search among files, so we don't use it (for now)
  NSImage *image2;
  image2 = [NSImage imageNamed: [NSString stringWithUTF8String: SDATA (file)]];
  if (image2 != nil) // && [image2 isKindOfClass:[EmacsImage class]])
    {
      [(EmacsImage *)image2 reference];
      return image2;
    }
  #endif


  /* Search bitmap-file-path for the file, if appropriate.  */
  found = x_find_image_file (file);
  if (!STRINGP (found))
    return nil;

  image = [[EmacsImage alloc] initByReferencingFile:
                     [NSString stringWithUTF8String: SDATA (found)]];

  // image = [NSImage imageNamed: [NSString stringWithUTF8String: SDATA (found)]];


#if 0
#if defined (NS_IMPL_COCOA) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
  imgRep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
#else
  imgRep = [image bestRepresentationForDevice: nil];
#endif
#else

  // we'll optimize for the main screen.
  // needed to pick the right representation e.g., when HiDPI image is provided.
  if ([image respondsToSelector: @selector (bestRepresentationForRect:context:hints:)])
    {
      // Choose the smallest (full-resolution) image representation
      imgRep = [image bestRepresentationForRect: NSMakeRect(100,100,2,2)  context:nil hints: nil];
    }
  else
    {
      imgRep = [image bestRepresentationForDevice: nil];
    }
#endif

  if (imgRep == nil)
    {
      [image release];
      return nil;
    }
  
  // Respect DPI?
  
  /* The next two lines cause the DPI of the image to be ignored.
     This seems to be the behavior users expect. */

  if (EQ (Qt, Vns_true_dpi_images_filename_string) ||
      (STRINGP (Vns_true_dpi_images_filename_string) &&
       strstr (SDATA (file), SDATA (Vns_true_dpi_images_filename_string))))
    {
      // this would retain the size:
      // [image setSize: NSMakeSize([image size].width, [image size].height)];

      // points = pixels for this port
      // so we need to scale the image.

      // NS assumes 72dpi= 72/25.4 pix/mm
      // So we adjust according to the CoreGraphics DPI information

      // use userSpaceScaleFactor?

      NSScreen *screen = [NSScreen mainScreen];
      CGDirectDisplayID displayID = (CGDirectDisplayID)[[[screen deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
      CGSize physicalSize = CGDisplayScreenSize (displayID);
      CGRect bounds = CGDisplayBounds (displayID);
      float resx = bounds.size.width / physicalSize.width; // pixels per mm
      float resy = bounds.size.height / physicalSize.height;


      [image setScalesWhenResized: YES];
      [image setSize: NSMakeSize([image size].width*resx / (72.0/25.4),  [image size].height*resy / (72.0/25.4))];

    }
  else
    {
      [image setScalesWhenResized: YES];
      [image setSize: NSMakeSize([imgRep pixelsWide], [imgRep pixelsHigh])];
    }

  [image setName: [NSString stringWithUTF8String: SDATA (file)]];
  [image reference];
  ImageList = [image imageListSetNext: ImageList];

  return image;
}


- reference
{
  refCount++;
  return self;
}


- imageListSetNext: (id)arg
{
  imageListNext = arg;
  return self;
}


- imageListNext
{
  return imageListNext;
}


- (void)dealloc
{
  id list = ImageList;

  if (refCount > 1)
    {
      refCount--;
      return;
    }

  [stippleMask release];

  if (list == self)
    ImageList = imageListNext;
  else
    {
      while (list != nil && [list imageListNext] != self)
        list = [list imageListNext];
      [list imageListSetNext: imageListNext];
    }

  [super dealloc];
}


- initFromXBM: (unsigned char *)bits width: (int)w height: (int)h
         flip: (BOOL)flip
{
  return [self initFromSkipXBM: bits width: w height: h flip: flip length: 0];
}


- initFromSkipXBM: (unsigned char *)bits width: (int)w height: (int)h
             flip: (BOOL)flip length: (int)length;
{
  int bpr = (w + 7) / 8;
  unsigned char *planes[5];

  [self initWithSize: NSMakeSize (w, h)];

  bmRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                    pixelsWide: w pixelsHigh: h
                                    bitsPerSample: 8 samplesPerPixel: 4
                                    hasAlpha: YES isPlanar: YES
                                    colorSpaceName: NSCalibratedRGBColorSpace
                                    bytesPerRow: w bitsPerPixel: 0];

  [bmRep getBitmapDataPlanes: planes];
  {
    /* pull bits out to set the (bytewise) alpha mask */
    int i, j, k;
    unsigned char *s = bits;
    unsigned char *alpha = planes[3];
    unsigned char swt[16] = {0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13,
                             3, 11, 7, 15};
    unsigned char c, bitPat;

    for (j = 0; j < h; j++)
      for (i = 0; i < bpr; i++)
        {
          if (length)
            {
              unsigned char s1, s2;
              while (*s++ != 'x' && s < bits + length);
              if (s >= bits + length)
                {
                  [bmRep release];
                  return nil;
                }
#define hexchar(x) (isdigit (x) ? x - '0' : x - 'a' + 10)
              s1 = *s++;
              s2 = *s++;
              c = hexchar (s1) * 0x10 + hexchar (s2);
            }
          else
            c = *s++;

          bitPat = flip ? swt[c >> 4] | (swt[c & 0xf] << 4) : c ^ 255;
          for (k =0; k<8; k++)
            {
              *alpha++ = (bitPat & 0x80) ? 0xff : 0;
              bitPat <<= 1;
            }
        }
  }

  [self addRepresentation: bmRep];

  bzero (planes[0], w*h);
  bzero (planes[1], w*h);
  bzero (planes[2], w*h);
  [self setXBMColor: [NSColor blackColor]];
  return self;
}


/* Set color for a bitmap image (see initFromSkipXBM).  Note that the alpha
   is used as a mask, so we just memset the entire array. */
- setXBMColor: (NSColor *)color
{
  NSSize s = [self size];
  int len = (int) s.width * s.height;
  unsigned char *planes[5];
  CGFloat r, g, b, a;
  NSColor *rgbColor;

  if (bmRep == nil || color == nil)
    return;

  if ([color colorSpaceName] != NSCalibratedRGBColorSpace)
    rgbColor = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  else
    rgbColor = color;

  [rgbColor getRed: &r green: &g blue: &b alpha: &a];

  [bmRep getBitmapDataPlanes: planes];

  /* we used to just do this, but Cocoa seems to have a bug when rendering
     an alpha-masked image onto a dark background where it bloats the mask */
   /* memset (planes[0..2], r, g, b*0xff, len); */
  {
    int i, len = s.width*s.height;
    int rr = r * 0xff, gg = g * 0xff, bb = b * 0xff;
    for (i =0; i<len; i++)
      if (planes[3][i] != 0)
        {
          planes[0][i] = rr;
          planes[1][i] = gg;
          planes[2][i] = bb;
        }
  }
}


- initForXPMWithDepth: (int)depth width: (int)width height: (int)height
{
  NSSize s = {width, height};
  int i;

  [self initWithSize: s];

  bmRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                  pixelsWide: width pixelsHigh: height
                                  /* keep things simple for now */
                                  bitsPerSample: 8 samplesPerPixel: 4 /*RGB+A*/
                                  hasAlpha: YES isPlanar: YES
                                  colorSpaceName: NSCalibratedRGBColorSpace
                                  bytesPerRow: width bitsPerPixel: 0];

  [bmRep getBitmapDataPlanes: pixmapData];
  for (i =0; i<4; i++)
    bzero (pixmapData[i], width*height);
  [self addRepresentation: bmRep];
  return self;
}


/* attempt to pull out pixmap data from a BitmapImageRep; returns NO if fails */
- (void) setPixmapData
{
  NSEnumerator *reps;
  NSImageRep *rep;

  reps = [[self representations] objectEnumerator];
  while (rep = (NSImageRep *) [reps nextObject])
    {
      if ([rep respondsToSelector: @selector (getBitmapDataPlanes:)])
        {
          bmRep = (NSBitmapImageRep *) rep;
          onTiger = [bmRep respondsToSelector: @selector (colorAtX:y:)];

          if ([bmRep numberOfPlanes] >= 3)
              [bmRep getBitmapDataPlanes: pixmapData];

          /* The next two lines cause the DPI of the image to be ignored.
             This seems to be the behavior users expect. */
	  [self setScalesWhenResized: YES];
	  [self setSize: NSMakeSize([bmRep pixelsWide], [bmRep pixelsHigh])];

          break;
        }
    }
}


/* note; this and next work only for image created with initForXPMWithDepth,
         initFromSkipXBM, or where setPixmapData was called successfully */
/* return ARGB */
- (unsigned long) getPixelAtX: (int)x Y: (int)y
{
  if (bmRep == nil)
    return 0;

  /* this method is faster but won't work for bitmaps */
  if (pixmapData[0] != NULL)
    {
      int loc = x + y * [self size].width;
      return (pixmapData[3][loc] << 24) /* alpha */
       | (pixmapData[0][loc] << 16) | (pixmapData[1][loc] << 8)
       | (pixmapData[2][loc]);
    }
  else if (onTiger)
    {
      NSColor *color = [bmRep colorAtX: x y: y];
      CGFloat r, g, b, a;
      [color getRed: &r green: &g blue: &b alpha: &a];
      return ((int)(a * 255.0) << 24)
        | ((int)(r * 255.0) << 16) | ((int)(g * 255.0) << 8)
        | ((int)(b * 255.0));

    }
  return 0;
}

- (void) setPixelAtX: (int)x Y: (int)y toRed: (unsigned char)r
               green: (unsigned char)g blue: (unsigned char)b
               alpha:(unsigned char)a;
{
  if (bmRep == nil)
    return;

  if (pixmapData[0] != NULL)
    {
      int loc = x + y * [self size].width;
      pixmapData[0][loc] = r;
      pixmapData[1][loc] = g;
      pixmapData[2][loc] = b;
      pixmapData[3][loc] = a;
    }
  else if (onTiger)
    {
      [bmRep setColor:
               [NSColor colorWithCalibratedRed: (r/255.0) green: (g/255.0)
                                          blue: (b/255.0) alpha: (a/255.0)]
                  atX: x y: y];
    }
}

- (void) setAlphaAtX: (int) x Y: (int) y to: (unsigned char) a
{
  if (bmRep == nil)
    return;

  if (pixmapData[0] != NULL)
    {
      int loc = x + y * [self size].width;

      pixmapData[3][loc] = a;
    }
  else if (onTiger)
    {
      NSColor *color = [bmRep colorAtX: x y: y];
      color = [color colorWithAlphaComponent: (a / 255.0)];
      [bmRep setColor: color atX: x y: y];
    }
}

/* returns a pattern color, which is cached here */
- (NSColor *)stippleMask
{
  if (stippleMask == nil)
      stippleMask = [[NSColor colorWithPatternImage: self] retain];
  return stippleMask;
}

@end

// arch-tag: 6b310280-6892-4e5e-8f34-41c4d384874f
