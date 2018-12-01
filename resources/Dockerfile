FROM ballerina/ballerina:<ballerina_version>
RUN mkdir /ballerina/mongodb
COPY wso2-mongodb-<mongodb_module_version>.zip /ballerina/mongodb/
RUN unzip /ballerina/mongodb/wso2-mongodb-<mongodb_module_version>.zip -d /ballerina/mongodb/
RUN  cd /ballerina/mongodb/ && printf '/ballerina/runtime' | sh install.sh
RUN rm -r /ballerina/mongodb