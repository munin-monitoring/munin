--  EMPTY the state DB
DELETE FROM state;
DELETE FROM stats;
DELETE FROM url;
DELETE FROM ds_attr;
DELETE FROM ds;
DELETE FROM service_attr;
DELETE FROM service_categories;
DELETE FROM service;
DELETE FROM node_attr;
DELETE FROM node;
DELETE FROM grp;
DELETE FROM param;
VACUUM FREE;
