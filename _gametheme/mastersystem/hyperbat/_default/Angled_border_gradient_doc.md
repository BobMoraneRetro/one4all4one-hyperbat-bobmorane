# Documentation du shader Perspective avec Bordure pour RetroBat

Ce document explique comment utiliser le shader `Angled_border_gradient.glsl` dans un thème RetroBat / Batocera.

---

## 1. Placement du shader

1. Placez le fichier GLSL dans le dossier de votre thème, par exemple :

```
<themePath>/_viewgame/fanartstar/Angled_border_gradient.glsl
```

2. Dans le XML du thème, référencez le shader avec la balise `<path>` :

```xml
<path>${themePath}/_viewgame/fanartstar/Angled_border_gradient.glsl</path>
```

> Cette balise doit être utilisée dans l’élément `<image>` ou `<video>` correspondant au fanart ou au snap que vous souhaitez modifier.

---

## 2. Paramètres du shader

| Paramètre                | Type       | Description | Exemple |
|---------------------------|-----------|------------|---------|
| `borderSize`              | float     | Largeur de la bordure en pixels relatifs à la hauteur de la texture | 5 |
| `tiltAngle`               | float     | Inclinaison verticale de la perspective (en degrés) | 0 |
| `tiltAngleX`              | float     | Inclinaison horizontale de la perspective (en degrés) | 40 |
| `perspectiveDepth`        | float     | Profondeur de la perspective | 0.7 |
| `borderColorStart`        | vec4      | Couleur de départ du dégradé | 0 0 0 1 |
| `borderColorEnd`          | vec4      | Couleur de fin du dégradé | 1 1 1 1 |
| `textureSize`             | vec2      | Taille de la texture (pixels) | 1920 1080 |
| `gradientMode`            | int       | Mode du dégradé : <br>0 = vertical<br>1 = horizontal<br>2 = diagonale TL→BR<br>3 = diagonale TR→BL<br>4 = radial | 4 |
| `gradientMix`             | float     | Point exact où la couleur change (0.0 à 1.0) | 0.5 |
| `gradientTransition`      | float     | Largeur de transition douce autour de `gradientMix` | 1.2 |

### 2.1 Mode dégradé (`gradientMode`)

- **0 : Vertical** → le dégradé va du haut vers le bas.
- **1 : Horizontal** → le dégradé va de la gauche vers la droite.
- **2 : Diagonale TL→BR** → du coin supérieur gauche au coin inférieur droit.
- **3 : Diagonale TR→BL** → du coin supérieur droit au coin inférieur gauche.
- **4 : Radial** → depuis le centre vers les bords.

> Pour reproduire le style original avant l’ajout de `gradientMix` et `gradientTransition`, utilisez `gradientMode = 4` (radial), `gradientMix = 0.5` et `gradientTransition = 1.2`.

### 2.2 Ajuster le point de transition (`gradientMix`)

- Définit l’endroit exact où le dégradé passe de `borderColorStart` à `borderColorEnd`.
- **Valeur par défaut : 0.5** (milieu de l’image).
- `0.0` → début de l’image, `1.0` → fin de l’image.

### 2.3 Ajuster la douceur (`gradientTransition`)

- Définit l’étalement du dégradé autour du `gradientMix`.
- **Valeur par défaut : 1.2** pour un effet progressif.
- Plus petit → transition plus nette, plus grand → transition plus douce.

---

## 3. Exemple XML complet

```xml
<image>
    <path>${themePath}/_viewgame/fanartstar/perspective_border.glsl</path>
    <borderSize>5</borderSize>
    <tiltAngle>0</tiltAngle>
    <tiltAngleX>40</tiltAngleX>
    <perspectiveDepth>0.7</perspectiveDepth>
    <borderColorStart>0 0 0 1</borderColorStart>
    <borderColorEnd>1 1 1 1</borderColorEnd>
    <textureSize>1920 1080</textureSize>
    <gradientMode>4</gradientMode>
    <gradientMix>0.5</gradientMix>
    <gradientTransition>1.2</gradientTransition>
</image>
```

> Avec ces valeurs, vous obtiendrez un effet proche de l’original, avec un dégradé radial centré et une bordure bien visible.

---

## 4. Conseils d’utilisation

- **Textures HD** : ajustez `textureSize` pour correspondre à la taille réelle de votre image afin que la bordure soit proportionnelle.
- **Bordure fine** : `borderSize` autour de 2-5 fonctionne bien pour la plupart des fanarts.
- **Perspective** : `tiltAngleX` autour de 30-45 crée un effet dynamique sans trop déformer l’image.
- **Radial** : recommandé pour un rendu naturel autour des fanarts.

---

**Auteur :** Documentation générée pour RetroBat / Batocera
**Shader :** Angled_border_gradient.glsl

