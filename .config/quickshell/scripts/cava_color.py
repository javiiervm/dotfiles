import sys, colorsys
from PIL import Image

def get_contrast_color(img_path):
    try:
        # 1. Abrimos la imagen y la reducimos a 1x1 píxel para sacar la media de color de todo el fondo
        img = Image.open(img_path).convert('RGB')
        img = img.resize((1, 1), resample=Image.Resampling.LANCZOS)
        r, g, b = img.getpixel((0, 0))
        
        # 2. Convertimos RGB a HSL (Matiz, Luminosidad, Saturación)
        h, l, s = colorsys.rgb_to_hls(r/255.0, g/255.0, b/255.0)
        
        # 3. Aumentamos un poco la saturación para que las barras tengan colores vivos, no grisáceos
        s = min(1.0, s * 1.3)
        
        # 4. MAGIA DEL CONTRASTE: 
        # Si la luminosidad del fondo es media/alta (> 0.4), hacemos la barra muy oscura (0.15)
        # Si el fondo es oscuro, hacemos la barra muy brillante (0.85)
        new_l = 0.15 if l > 0.4 else 0.85 
        
        # 5. Volvemos a convertir a formato HEX para dárselo a Quickshell
        nr, ng, nb = colorsys.hls_to_rgb(h, new_l, s)
        return f"#{int(nr*255):02x}{int(ng*255):02x}{int(nb*255):02x}"
    except Exception:
        return "#ffffff" # Color por defecto si algo falla

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(get_contrast_color(sys.argv[1]))