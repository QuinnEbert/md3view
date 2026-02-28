APP_NAME = MD3View
BUNDLE = $(APP_NAME).app
EXECUTABLE = md3view

CC = clang
OBJC = clang

CFLAGS = -Wall -O2 -DGL_SILENCE_DEPRECATION
OBJCFLAGS = $(CFLAGS) -fobjc-arc -Wno-nullability-completeness -Wno-deprecated-declarations

FRAMEWORKS = -framework Cocoa -framework OpenGL -framework QuartzCore -framework UniformTypeIdentifiers
LIBS = -lz

MINIZIP_SRC = minizip/unzip.c minizip/ioapi.c
OBJC_SRC = main.m PK3Archive.m MD3Model.m SkinParser.m AnimationConfig.m \
           TextureCache.m ModelRenderer.m ModelView.m MD3PlayerModel.m

MINIZIP_OBJ = $(MINIZIP_SRC:.c=.o)
OBJC_OBJ = $(OBJC_SRC:.m=.o)

ALL_OBJ = $(MINIZIP_OBJ) $(OBJC_OBJ)

.PHONY: all clean

all: $(BUNDLE)

$(EXECUTABLE): $(ALL_OBJ)
	$(OBJC) $(OBJCFLAGS) -o $@ $^ $(FRAMEWORKS) $(LIBS)

$(BUNDLE): $(EXECUTABLE) Info.plist
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(BUNDLE)/Contents/MacOS/
	cp Info.plist $(BUNDLE)/Contents/

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.m
	$(OBJC) $(OBJCFLAGS) -c -o $@ $<

clean:
	rm -f $(ALL_OBJ) $(EXECUTABLE)
	rm -rf $(BUNDLE)
