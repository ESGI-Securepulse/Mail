FROM alpine:3.19

RUN apk add --no-cache \
    dovecot dovecot-lmtpd dovecot-pop3d dovecot-ldap dovecot-pigeonhole-plugin \
    curl jq iproute2 tini \
    && mkdir -p /var/mail \
    && addgroup -g 5000 vmail \
    && adduser -D -u 5000 -G vmail -h /var/mail vmail \
    && chown vmail:vmail /var/mail

COPY conf/dovecot.conf        /etc/dovecot/dovecot.conf
COPY conf/10-auth.conf        /etc/dovecot/conf.d/
COPY conf/10-mail.conf        /etc/dovecot/conf.d/
COPY conf/10-ssl.conf         /etc/dovecot/conf.d/
COPY conf/10-master.conf      /etc/dovecot/conf.d/
COPY conf/10-namespace.conf   /etc/dovecot/conf.d/
COPY conf/90-replication.conf /etc/dovecot/conf.d/
COPY conf/dovecot-ldap.conf   /etc/dovecot/dovecot-ldap.conf
COPY entrypoint.sh            /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 143 993 110 995 24 4177 12345

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
