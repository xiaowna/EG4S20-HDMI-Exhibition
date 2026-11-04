from PIL import Image
def reference_frame(state, glyphs, spectrum=True, music=(0,0,4,0),fine=None):
    active,page,bright,gain,fade,wave,product,auto_page,auto = state
    selected = 4 if auto_page else page
    if music and music[0]: selected=5
    bottom,footer=432,400
    texts = [(144,104,2,'播放设置',0x70d6bc),
             (440,108,1,'产品' if product else '演示',0xb6e7d7),
             (192,footer,1,'←→调节  K2下项  K4返回',0x93a9b4)]
    labels=['亮度','对比度','切图渐变','彩色频谱' if spectrum else '音频波形','自动轮播']
    if music is not None: labels.extend(['背景音乐','时间设置'])
    for row,label in enumerate(labels):
        yy = 160+32*row
        color = 0x8298a4 if (row==4 and not product) or (row==5 and (not product or music[2]==0)) else 0xe7efec
        texts.append((152,yy,2,label,color))
        if row==0:
            value = (f'{fine[0]:+4d}' if fine[0] else '   0') if fine is not None else [' -64',' -32','   0',' +32',' +64'][bright]
            texts.append((416,yy+4,1,value,color))
        elif row==1:
            texts.append((416,yy+4,1,(f'{fine[1]:3d}%' if fine is not None else [' 50%',' 75%','100%','125%','150%'][gain]),color))
        elif row==5:
            _,choice,count,playing=music
            if choice!=playing:color=0xb6e7d7
            texts.append((416,yy+4,1,f'{choice+1 if count else 0}/{count} ',color))
        elif row<5:
            texts.append((416,yy,2,'开启' if [fade,wave,auto][row-2] else '关闭',color))
    text_pixels = {}
    for xx,yy,scale,text,color in texts:
        for i,ch in enumerate(text):
            bitmap = glyphs[ch]
            for gy,line in enumerate(bitmap):
                for gx,bit in enumerate(line):
                    if bit=='1':
                        for dy in range(scale):
                            for dx in range(scale):
                                text_pixels[(xx+i*16*scale+gx*scale+dx,yy+gy*scale+dy)] = color
    data = []
    image = Image.new('RGB',(640,480))
    pixels = []
    for y in range(480):
        for x in range(640):
            rgb = ((x&255)<<16)|((y&255)<<8)|((x^y)&255)
            panel = 112<=x<528 and 80<=y<bottom and (120<=x<520 or 88<=y<bottom-8)
            shadow = 120<=x<536 and 88<=y<bottom+8 and (128<=x<528 or 96<=y<bottom)
            visible = active and (panel or shadow)
            color = rgb
            if visible:
                color = (rgb&0xfefefe)>>1
                if panel:
                    inner = 114<=x<526 and 82<=y<bottom-2 and (122<=x<518 or 90<=y<bottom-10)
                    color = 0x162737
                    if not inner: color=0x3b5363
                    elif (148<=y<150 or footer-20<=y<footer-18) and 128<=x<512: color=0x3b5363
                    elif 416<=x<496 and 100<=y<132: color=0x203641
                    elif 128<=x<512 and 156+32*selected<=y<188+32*selected:
                        color=0x70d6bc if x<132 else 0x203f47
                    for row in range(5):
                        dy=y-(160+32*row)
                        if fine is not None and row<2 and 344<=x<472 and 26<=dy<30:
                            count=fine[0]+64 if row==0 else ((fine[1]-50)*41)//32
                            color=0x70d6bc if x-344<count else 0x405865
                        elif row<2 and 344<=x<464 and 26<=dy<30:
                            segment,offset=divmod(x-344,24)
                            color=(0x162737 if offset>=20 else
                                   (0x70d6bc if segment<=[bright,gain][row] else 0x405865))
                        if row>=2 and 344<=x<396 and 8<=dy<24:
                            enabled=[fade,wave,auto][row-2]
                            disabled=row==4 and not product
                            color=0x347e6c if enabled and not disabled else 0x405865
                            if 10<=dy<22 and ((380<=x<392) if enabled else (348<=x<360)):
                                color=0x8298a4 if disabled else 0xedf6ef
                    color=text_pixels.get((x,y),color)
            data.append((int(bool(visible))<<24)|color)
            pixels.append(((color>>16)&255,(color>>8)&255,color&255))
    image.putdata(pixels)
    return data,image

