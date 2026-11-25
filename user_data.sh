#!/bin/bash
set -eux

exec > /var/log/user-data.log 2>&1

dnf update -y
dnf install -y httpd php php-mysqlnd php-gd php-xml php-mbstring php-opcache mariadb105 wget tar curl

systemctl enable httpd
systemctl start httpd

mkdir -p /var/www/html
echo "OK" > /var/www/html/health.html

cd /tmp
rm -rf wordpress latest.tar.gz

wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz

rm -rf /var/www/html/*
cp -r wordpress/* /var/www/html/

echo "OK" > /var/www/html/health.html

cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

sed -i "s/database_name_here/${db_name}/" /var/www/html/wp-config.php
sed -i "s/username_here/${db_user}/" /var/www/html/wp-config.php
sed -i "s/password_here/${db_password}/" /var/www/html/wp-config.php
sed -i "s/localhost/${db_host}/" /var/www/html/wp-config.php

chown -R apache:apache /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

systemctl restart httpd