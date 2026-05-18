FROM alpine:3.19

RUN apk add --no-cache \
    postfix postfix-ldap postfix-pcre \
    cyrus-sasl cyrus-sasl-digestmd5 \
    curl iproute2 tini busybox-extras

COPY conf/main.cf           /etc/postfix/main.cf
COPY conf/master.cf         /etc/postfix/master.cf
COPY conf/ldap-vmailbox.cf  /etc/postfix/ldap-vmailbox.cf
COPY conf/ldap-aliases.cf   /etc/postfix/ldap-aliases.cf
COPY entrypoint.sh          /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 25 587

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
