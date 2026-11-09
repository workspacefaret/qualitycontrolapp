# Copie a config.psd1 y ajuste. NUNCA escriba contrasenas aqui (con -Autenticacion Sql la clave se pide al ejecutar).
# Los scripts aceptan estos mismos valores como parametros; este archivo es solo una referencia.
@{
    Servidor           = '192.168.1.230'          # SAP_NEW
    Base               = 'calidad_db'
    Autenticacion      = 'Windows'                # Windows | Sql
    Usuario            = ''                       # solo con Sql
    ConfiarCertificado = $true
    RutaRespaldo       = 'D:\Respaldos\calidad'   # carpeta EN EL SERVIDOR SQL (la escribe el servicio de SQL Server)
}
