# Шпаргалка ко дню 6: Active Directory

## Уровни

| Уровень | Что это |
|---|---|
| Лес | Контейнер для всего и настоящая граница безопасности |
| Дерево | Домены со связанными именами |
| Домен | Административная единица, здесь это `{DOMAIN}` |
| Подразделение (OU) | Папки для упорядочивания объектов и применения политик |
| Объекты | Пользователи, компьютеры и группы |

**Подразделение** упорядочивает объекты и служит для применения GPO. **Группа** предоставляет разрешения. Это разные вещи.

## Перечисление

```powershell
Get-ADUser     -Filter * -Properties *
Get-ADComputer -Filter * -Properties *
Get-ADGroup    -Filter * -Properties *
Get-ADGroupMember "Имя группы"
Get-ADPrincipalGroupMembership $env:USERNAME
Get-ADDomain
```

> Самый важный урок дня: `Get-ADUser` возвращает лишь несколько полей из тридцати, которые есть у объекта. Всё интересное находится в `-Properties *`.

Поля, которые почти никто не проверяет и в которых часто что-то хранится: `Description`, `info`, `comment`, `OperatingSystem`, `ServicePrincipalName`, `LastLogonDate`, `employeeNumber`, `mail`.

## Фильтрация

```powershell
Get-ADUser -Filter { Enabled -eq $true }
Get-ADUser -Filter { ServicePrincipalName -like "*" } -Properties ServicePrincipalName
Get-ADUser -Filter * -Properties Description | Where-Object { $_.Description -match "что-то" }
```

## Ваши собственные привилегии

```cmd
whoami /groups
whoami /priv
whoami /user
```

## На чём держится каталог

| Компонент | Роль |
|---|---|
| DNS | Клиенты находят контроллер домена по записям SRV. Без DNS AD не работает |
| LDAP (389) | Чтение и запись каталога |
| Kerberos (88) | Проверка подлинности с помощью билетов |
| Глобальный каталог (3268) | Индекс всего леса |

> В локализованной Windows встроенные группы переведены: скрипт, который ищет `Domain Admins` на русскоязычном сервере, ничего не найдёт, ведь там группа называется «Администраторы домена». Неизменным остаётся только **SID**.
