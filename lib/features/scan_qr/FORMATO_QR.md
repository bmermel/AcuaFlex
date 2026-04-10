# Formato de QR para AcuaFlex

## Formato nuevo (recomendado) – con identificador único

El QR debe contener un **JSON** con al menos los siguientes campos.  
**orderId** es obligatorio para identificación confiable y detección de duplicados.

```json
{
  "orderId": "PED-12345",
  "nombre": "Juan Perez",
  "telefono": "1122334455",
  "dni": "30111222",
  "direccion": "Av. Corrientes 1234",
  "codigoPostal": "1043",
  "localidad": "CABA",
  "provincia": "CABA",
  "observaciones": "Entregar de 9 a 13"
}
```

### Campos

| Campo          | Obligatorio | Descripción                          |
|----------------|-------------|--------------------------------------|
| **orderId**    | Sí          | Identificador único del pedido       |
| **nombre**     | Sí          | Nombre del destinatario              |
| **dni**        | Sí          | DNI                                  |
| **direccion**  | Sí          | Dirección principal                  |
| **telefono**   | No          | Teléfono                             |
| **observaciones** | No       | Observaciones                        |
| **codigoPostal**  | No       | Código postal                        |
| **localidad**     | No       | Localidad                            |
| **provincia**    | No       | Provincia                            |
| **direccionCompleta** | No  | Dirección completa (si difiere)       |

### Duplicados con orderId

- Si ya existe una entrega con el mismo **orderId** para el **mismo conductor** → se considera duplicado propio y no se crea otra.
- Si ya existe una entrega con el mismo **orderId** para **otro conductor** → se muestra un diálogo y se permite “Agregar igual” si se desea.

---

## Formato viejo (sin orderId) – compatibilidad

Si el QR no incluye **orderId** (solo nombre, dni, direccion, etc.):

1. La app **no rompe**: se valida nombre, DNI y dirección como antes.
2. Se muestra un **mensaje** indicando que el QR no tiene identificador único y que el formato ideal es el nuevo.
3. Se ofrece **“Agregar igual”** usando la lógica secundaria (DNI + dirección) para detectar duplicados.  
   Esta lógica puede dar falsos positivos o negativos (mismo DNI y dirección en pedidos distintos, o mismo pedido con dirección escrita distinto).

Recomendación: migrar a QRs con **orderId** para evitar duplicados y ambigüedades.
