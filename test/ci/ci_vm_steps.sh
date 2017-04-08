#!/bin/bash
set -e
set -x

cd /workspace
gem install bundler --no-doc
bundle install

ruby --version
mongod --version

rake ci_vm