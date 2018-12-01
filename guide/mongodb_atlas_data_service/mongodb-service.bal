import ballerina/http;
import ballerina/log;
import ballerinax/kubernetes;
import wso2/mongodb;

// The configuration fields can be obtained from the MongoDB Atlas URI components
mongodb:Client conn = new({
    host: "cluster0-shard-00-00-munbd.gcp.mongodb.net:27017,cluster0-shard-00-01-munbd.gcp.mongodb.net:27017,cluster0-shard-00-02-munbd.gcp.mongodb.net:27017",
    dbName: "BallerinaDemoDB",
    username: "<db_username>",
    password: "<db_password>",
    options: { authSource: "admin", sslEnabled: true, retryWrites: true, replicaSet: "Cluster0-shard-0" }
});

// It is possible to use the direct connection string in the client configuration, as well
//mongodb:Client conn = new({
//    dbName: "BallerinaDemoDB",
//    options : { url: "mongodb://<db_username>:<db_password>@cluster0-shard-00-00-munbd.gcp.mongodb.net:27017,cluster0-shard-00-01-munbd.gcp.mongodb.net:27017,cluster0-shard-00-02-munbd.gcp.mongodb.net:27017/BallerinaDemoDB?ssl=true&replicaSet=Cluster0-shard-0&authSource=admin&retryWrites=true"}
//});

// Also, the short SRV connection string can be used if the driver version is compatible with it
//mongodb:Client conn = new({
//    dbName: "BallerinaDemoDB",
//    options : { url: "mongodb+srv://testuser:test@cluster0-munbd.gcp.mongodb.net/test?retryWrites=true"}
//});

@kubernetes:Service {
    name:"search-service",
    serviceType:"LoadBalancer",
    port:80
}
listener http:Listener httpListener = new(9090);

@kubernetes:Deployment {
    enableLiveness:true,
    image:"<user>/ballerina_mongodbaltas_service:latest",
    push:true,
    username:"<user>",
    password:"<password>",
    baseImage: "mongodb-ballerina:1.0",
    imagePullPolicy: "Always"
}

// By default, Ballerina exposes a service via HTTP/1.1.
service searchService on httpListener {

    @http:ResourceConfig {
        path:"/search/{keyword}"
    }
    resource function search(http:Caller caller, http:Request req, string keyword) {
        http:Response res = new;

        json searchQuery = { "$text": { "$search": keyword } };

        var jsonRet = conn->find("Books", searchQuery);
        if (jsonRet is json) {
            json[] dataArray = <json[]>jsonRet;
            if (dataArray.length() == 0) {
                res.setPayload({ "Status": "No data found for the keyword: `" + untaint keyword + "`"});
            } else {
                res.setPayload({ "Status": "Data found", "Results": jsonRet });
            }
        } else {
            log:printError("Error", err = jsonRet);
            res.statusCode = 500;
            res.setPayload({ "Status": "Error occured during the search" });
        }

        // Send the response back to the caller.
        var result = caller->respond(res);
        if (result is error) {
            log:printError("Error sending response", err = result);
        }
    }
}
