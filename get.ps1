# Remote entry point: create an advanced script scope before invoking the installer.
# Invoke-Expression alone does not initialize PSCmdlet in Windows PowerShell 5.1.
$installer = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/ChildeRolando/majsoul_moqie/main/install.ps1'
& ([scriptblock]::Create($installer))
