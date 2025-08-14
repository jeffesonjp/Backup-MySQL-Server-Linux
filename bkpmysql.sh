#!/bin/bash

set -e
set -o pipefail

DATE=$(date +"%d%m%Y")
HOUR=$(date +"%-H")
if [[ $HOUR -ge 6 ]] && [[ $HOUR -lt 12 ]]; then
    TURNO="M"
elif [[ $HOUR -ge 12 ]] && [[ $HOUR -lt 18 ]]; then
    TURNO="T"
else
    TURNO="N"
fi

BACKUP_BASE="MySQL_8_${DATE}_${TURNO}"
BACKUP_DIR="/home/MySQLServer/backups/${BACKUP_BASE}"
BACKUP_7Z="/home/MySQLServer/backups/${BACKUP_BASE}.7z"
LOG_FILE="/home/MySQLServer/logs/${BACKUP_BASE}_log.txt"
HOST_PROFILES="perfil1 perfil2 perfil3"
EXCLUDE_DATABASES="information_schema performance_schema mysql sys banco-teste"

ano=$(date +%Y)
mes_num=$(date +%-m)
mes=$(LC_ALL=pt_BR.UTF-8 date +%B)
semestre=$(( (mes_num - 1) / 6 + 1 ))
primeiro_dia_semana=$(date -d "$ano-$mes_num-01" +%u)  # Dia da semana (1-7)
dia=$(date +%-d)  # Dia do mês sem zero inicial
semana=$(( (dia + primeiro_dia_semana - 1 ) / 7 + 1 ))
semana_formatada=$(printf "semana_%02d" $semana)
RCLONE_DEST="backupremoto:${ano}.${semestre}/8/${mes^}/${semana_formatada}/${DATE}"

log() {
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

handle_error() {
    log "[ERRO] $1"
    if [[ -d "$BACKUP_DIR" ]]; then
        log "Removendo diretório de backup temporário devido a erro: ${BACKUP_DIR}"
        rm -rf "$BACKUP_DIR"
    fi
    exit 1
}

log "Removendo backups antigos..."
rm -rf "/home/MySQLServer/backups" 2>> "$LOG_FILE"
log "Criando diretório de backup..."
mkdir -p "${BACKUP_DIR}" || handle_error "Diretório ${BACKUP_DIR} não pode ser criado"

log "Iniciando processo de backup: ${BACKUP_BASE}"
log "Criando diretório de backup: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

for PROFILE in ${HOST_PROFILES}; do
    log "Processando perfil: ${PROFILE}"

    DATABASES_LIST=$(mysql --login-path="${PROFILE}" -e "SHOW DATABASES;" 2>> "$LOG_FILE" | grep -Ev "Database|(${EXCLUDE_DATABASES// /|})")
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        handle_error "Falha ao listar bancos de dados para o perfil ${PROFILE}"
    fi

    if [[ -z "$DATABASES_LIST" ]]; then
        log "[AVISO] Nenhum banco de dados encontrado para backup no perfil ${PROFILE}."
        continue
    fi

    for DB in ${DATABASES_LIST}; do
        log "Processando banco de dados: ${DB}"

        TABLES_LIST=$(mysql --login-path="${PROFILE}" -D"${DB}" -e 'SHOW TABLES;' 2>> "$LOG_FILE" | awk '{print $1}' | grep -v '^Tables_in_')
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            log "[AVISO] Falha ao listar tabelas para o banco de dados ${DB}. Pulando para o próximo."
            continue
        fi

        if [[ -n "$TABLES_LIST" ]]; then
            for TABLE in ${TABLES_LIST}; do
                log "Exportando tabela: ${DB}_${TABLE}..."
                SQL_FILE="${BACKUP_DIR}/${DB}_${TABLE}.sql"
                
                echo "CREATE DATABASE IF NOT EXISTS \`${DB}\`;" > "${SQL_FILE}"
                echo "USE \`${DB}\`;" >> "${SQL_FILE}"

                mysqldump --login-path="${PROFILE}" \
                    --opt \
                    --single-transaction \
                    --column-statistics=FALSE \
                    "${DB}" "${TABLE}" >> "${SQL_FILE}" 2>> "$LOG_FILE"

                if [[ $? -ne 0 ]]; then
                    log "[AVISO] Falha no dump da tabela ${DB}_${TABLE}. O arquivo pode estar incompleto ou vazio."
                    rm -f "${SQL_FILE}"
                fi
            done
        else
            log "[INFO] Nenhuma tabela encontrada no banco de dados ${DB}."
        fi

        log "Exportando rotinas, eventos e triggers para: ${DB}..."
        ROUTINES_FILE="${BACKUP_DIR}/${DB}_routines.sql"
        
        echo "CREATE DATABASE IF NOT EXISTS \`${DB}\`;" > "${ROUTINES_FILE}"
        echo "USE \`${DB}\`;" >> "${ROUTINES_FILE}"

        mysqldump --login-path="${PROFILE}" \
            --no-data \
            --no-create-info \
            --routines \
            --events \
            --triggers \
            "${DB}" >> "${ROUTINES_FILE}" 2>> "$LOG_FILE"

        if [[ $? -ne 0 ]]; then
            log "[AVISO] Falha no dump de rotinas para o banco de dados ${DB}."
            rm -f "${ROUTINES_FILE}"
        fi
    done
done

if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
    handle_error "Nenhum arquivo de backup foi gerado. Abortando."
fi

log "Compactando arquivos de backup..."
7z a -t7z -m0=lzma -mx=5 -mfb=64 -md=32m -ms=on "${BACKUP_7Z}" "${BACKUP_DIR}/" >> "$LOG_FILE" 2>&1

log "Removendo diretório de trabalho..."
rm -rf "${BACKUP_DIR}"

log "Backup concluído: ${BACKUP_7Z} (Tamanho: $(du -h "${BACKUP_7Z}" | cut -f1))"

log "Enviando ${BACKUP_BASE}.7z para o Google Drive..."
log "Destino: ${RCLONE_DEST}"
/home/MySQLServer/rclone copy -Pv --log-file="${LOG_FILE}" "${BACKUP_7Z}" "${RCLONE_DEST}"

log "Enviando e-mail de notificação..."
sendEmail \
-f "remetente@mail.com" \
-u "Backup MySQL 8" \
-m "Backup Bancos ABC DEF GHI" \
-s smtp.gmail.com:587 \
-xu "remetente@mail.com" \
-xp "apps enh aun icas" \
-t "destinatario@mail.com" \
-a "${LOG_FILE}" \
-o tls=yes \
-o message-content-type=html \
-o message-charset=utf-8 \
-vv

log "Processo finalizado com sucesso."
exit 0
