package by.bsu.rct.bigdata;

import org.apache.spark.api.java.JavaRDD;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.sql.SparkSession;

public class LineCountDriverSpark
{
    private final SparkSession spark;

    public LineCountDriverSpark(SparkSession spark){
        this.spark = spark;
    }

    private void runApplication( String[] args ){

        JavaSparkContext jsc = new JavaSparkContext(spark.sparkContext());

        JavaRDD<String> rdd = jsc.textFile(args[0]);
        System.out.println("Number of lines: " +  rdd.count());
    }

    public static void main( String[] args ) throws Exception {
        if(args.length == 0)
            throw new Exception("Path to the source data was not passed");

        SparkSession.Builder sessionBuilder= SparkSession.builder().appName("Line count Spark App");
        if(System.getenv().containsKey("IDE_ENV")){
            sessionBuilder.master("local[*]");
        }

        SparkSession spark = sessionBuilder.getOrCreate();
        try(spark){
            new LineCountDriverSpark(spark).runApplication(args);
        }
    }
}