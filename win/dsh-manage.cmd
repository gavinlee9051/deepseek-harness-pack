@echo off
rem dsh-manage.cmd - convenience wrapper around dsh.ps1
rem Usage: dsh-manage [start|stop|restart|status|log|upgrade]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh.ps1" %*
