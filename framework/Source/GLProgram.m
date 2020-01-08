//  This is Jeff LaMarche's GLProgram OpenGL shader wrapper class from his OpenGL ES 2.0 book.
//  A description of this can be found at his page on the topic:
//  http://iphonedevelopment.blogspot.com/2010/11/opengl-es-20-for-ios-chapter-4.html


#import "GLProgram.h"
typedef void (*GLInfoFunction)(GLuint program, GLenum pname, GLint* params);
typedef void (*GLLogFunction) (GLuint program, GLsizei bufsize, GLsizei* length, GLchar* infolog);

@interface GLProgram()
- (BOOL)compileShader:(GLuint *)shader 
                 type:(GLenum)type 
               string:(NSString *)shaderString;
@end

// - MARK: <-- 实现 -->
@implementation GLProgram

@synthesize initialized = _initialized;
// - MARK: <-- 加载 shaderProgram -->
/** 直接从字符串编译 shaderProgram */
- (id)initWithVertexShaderString:(NSString *)vShaderString 
            fragmentShaderString:(NSString *)fShaderString;
{
    if ((self = [super init])) 
    {
        _initialized = NO;
        
        // - 初始化 attributes 和 uniforms 数组
        attributes = [[NSMutableArray alloc] init];
        
        // - 这里没用到
//        uniforms = [[NSMutableArray alloc] init];
        
        // - 创建一个program
        program = glCreateProgram();
        
        // - 编译顶点着色器
        if (![self compileShader:&vertShader 
                            type:GL_VERTEX_SHADER 
                          string:vShaderString])
        {
            NSLog(@"Failed to compile vertex shader");
        }
        
        // - 编译片元着色器
        if (![self compileShader:&fragShader 
                            type:GL_FRAGMENT_SHADER 
                          string:fShaderString])
        {
            NSLog(@"Failed to compile fragment shader");
        }
        
        // - 将两个着色器附加到着色器程序中
        glAttachShader(program, vertShader);
        glAttachShader(program, fragShader);
    }
    
    return self;
}

/** 用字符串和本地文件加载 shaderProgram */
- (id)initWithVertexShaderString:(NSString *)vShaderString 
          fragmentShaderFilename:(NSString *)fShaderFilename;
{
    NSString *fragShaderPathname = [[NSBundle mainBundle] pathForResource:fShaderFilename ofType:@"fsh"];
    NSString *fragmentShaderString = [NSString stringWithContentsOfFile:fragShaderPathname encoding:NSUTF8StringEncoding error:nil];
    
    if ((self = [self initWithVertexShaderString:vShaderString fragmentShaderString:fragmentShaderString])) 
    {
    }
    
    return self;
}

/** 用本地文件加载 shaderProgram */
- (id)initWithVertexShaderFilename:(NSString *)vShaderFilename 
            fragmentShaderFilename:(NSString *)fShaderFilename;
{
    NSString *vertShaderPathname = [[NSBundle mainBundle] pathForResource:vShaderFilename ofType:@"vsh"];
    NSString *vertexShaderString = [NSString stringWithContentsOfFile:vertShaderPathname encoding:NSUTF8StringEncoding error:nil];

    NSString *fragShaderPathname = [[NSBundle mainBundle] pathForResource:fShaderFilename ofType:@"fsh"];
    NSString *fragmentShaderString = [NSString stringWithContentsOfFile:fragShaderPathname encoding:NSUTF8StringEncoding error:nil];
    
    if ((self = [self initWithVertexShaderString:vertexShaderString fragmentShaderString:fragmentShaderString])) 
    {
    }
    
    return self;
}

 // - MARK: <-- 编译着色器程序 -->
- (BOOL)compileShader:(GLuint *)shader 
                 type:(GLenum)type 
               string:(NSString *)shaderString
{
//    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

    GLint status;
    const GLchar *source;
    
    source = 
      (GLchar *)[shaderString UTF8String];
    if (!source)
    {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    // - 创建着色器程序
    *shader = glCreateShader(type);
    
    // -  替换着色器对象中的源代码
    glShaderSource(*shader, 1, &source, NULL);
    
    // - 编译着色器中的代码
    glCompileShader(*shader);
    
    // - 获取着色器程序的编译状态
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);

	if (status != GL_TRUE)
	{
		GLint logLength;
        
        //- 获取着色器程序的 log日志的长度
		glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
		if (logLength > 0)
		{
			GLchar *log = (GLchar *)malloc(logLength);
            
            // - 获取着色器程序的日志
			glGetShaderInfoLog(*shader, logLength, &logLength, log);
            if (shader == &vertShader)
            {
                self.vertexShaderLog = [NSString stringWithFormat:@"%s", log];
            }
            else
            {
                self.fragmentShaderLog = [NSString stringWithFormat:@"%s", log];
            }

			free(log);
		}
	}	
	
//    CFAbsoluteTime linkTime = (CFAbsoluteTimeGetCurrent() - startTime);
//    NSLog(@"Compiled in %f ms", linkTime * 1000.0);

    return status == GL_TRUE;
}

// - MARK: <-- 这个shaderProgram中的所有用Attribute修饰的变量  -->
- (void)addAttribute:(NSString *)attributeName
{
    if (![attributes containsObject:attributeName])
    {
        [attributes addObject:attributeName];
        
        // - 绑定顶点属性索引绑定到数组的下标
        glBindAttribLocation(program, 
                             (GLuint)[attributes indexOfObject:attributeName],
                             [attributeName UTF8String]);
    }
}

// - 获取attributes变量对应的索引(即数组下标)
- (GLuint)attributeIndex:(NSString *)attributeName
{
    return (GLuint)[attributes indexOfObject:attributeName];
}

// - 获取uniform属性变量对应的索引
- (GLuint)uniformIndex:(NSString *)uniformName
{
    return glGetUniformLocation(program, [uniformName UTF8String]);
}

#pragma mark -
// - MARK: <-- 链接着色器程序 -->
- (BOOL)link
{
//    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

    GLint status;
    
    // - 链接着色器
    glLinkProgram(program);
    
    // - 获取着色器的连接状态
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (status == GL_FALSE)
        return NO;
    
    // - 链接完成后释放
    if (vertShader)
    {
        glDeleteShader(vertShader);
        vertShader = 0;
    }
    if (fragShader)
    {
        glDeleteShader(fragShader);
        fragShader = 0;
    }
    
    self.initialized = YES;

//    CFAbsoluteTime linkTime = (CFAbsoluteTimeGetCurrent() - startTime);
//    NSLog(@"Linked in %f ms", linkTime * 1000.0);

    return YES;
}

/** 使用着色器程序 */
- (void)use
{
    glUseProgram(program);
}

// - MARK: <-- 验证程序对象 -->
- (void)validate;
{
	GLint logLength;
	
    // - 验证程序对象
	glValidateProgram(program);
    
    // - 获取着色器程序的日志长度
	glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0)
	{
		GLchar *log = (GLchar *)malloc(logLength);
        
        // - 获取着色器程序的日志
		glGetProgramInfoLog(program, logLength, &logLength, log);
        self.programLog = [NSString stringWithFormat:@"%s", log];
		free(log);
	}	
}

// - MARK: <-- 释放着色器程序 -->
- (void)dealloc
{
    if (vertShader)
        glDeleteShader(vertShader);
        
    if (fragShader)
        glDeleteShader(fragShader);
    
    if (program)
        glDeleteProgram(program);
       
}

@end
