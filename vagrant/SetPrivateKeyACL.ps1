# 秘密鍵が置かれるフォルダの権限を、操作ユーザーのみ許可するよう設定します
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    # スクリプトを管理者権限で再実行
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Unrestricted -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# パスとユーザー名を指定します
$folderPath = "$PSScriptRoot/.vagrant/machines/visual-regression-test/virtualbox"
$userName = $args[0]

# ユーザー名が省略された場合は、現在のユーザー名を取得
if (-not $username) {
    $username = whoami
}

# ACL（Access Control List）を取得します
$acl = Get-Acl -Path $folderPath

# 現在のACLからすべてのアクセスルールを削除します
$acl.SetAccessRuleProtection($True, $False)

# ユーザーに対してフルコントロールのアクセスルールを作成します
$Permission = ($userName,"FullControl","ContainerInherit,ObjectInherit","None","Allow")
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission

# アクセスルールをACLに追加します
$acl.SetAccessRule($accessRule)

# 変更したACLをフォルダに適用します
Set-Acl -Path $folderPath -AclObject $acl